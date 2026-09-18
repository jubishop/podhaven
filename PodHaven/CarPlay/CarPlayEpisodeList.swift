// Copyright Justin Bishop, 2026

import AVFoundation
import CarPlay
import FactoryKit
import Foundation
import Logging
import Nuke
import SwiftUI

struct CarPlayEpisodeRow: Equatable {
  let id: Episode.ID
  let title: String
  let podcast: String
  let image: URL
  let duration: CMTime
  let currentTime: CMTime
  let downloaded: Bool
  let finished: Bool

  init(_ episode: ListablePodcastEpisode) {
    id = episode.id
    title = episode.title
    podcast = episode.podcastTitle
    image = episode.image
    duration = episode.duration
    currentTime = episode.currentTime
    downloaded = episode.cacheStatus == .cached
    finished = episode.finished
  }

  init(_ episode: OnDeck) {
    id = episode.id
    title = episode.title
    podcast = episode.podcastTitle
    image = episode.image
    duration = episode.duration
    currentTime = episode.currentTime
    downloaded = episode.cacheStatus == .cached
    finished = episode.finished
  }

  func detail(remaining: Bool, current: Bool, listeningState: Bool = false) -> String {
    var parts = [podcast]
    if duration.seconds.isFinite, duration.seconds > 0 {
      let time =
        remaining ? CMTime.seconds(max(0, duration.seconds - currentTime.safe.seconds)) : duration
      parts.append(remaining ? "\(time.shortDescription) remaining" : time.shortDescription)
    }
    if current { parts.append("Current episode") }
    if listeningState {
      parts.append(
        finished ? "Finished" : (currentTime.safe.seconds > 0 ? "In progress" : "Not started")
      )
    }
    if downloaded { parts.append("Downloaded") }
    return parts.joined(separator: " · ")
  }
}

@MainActor
final class CarPlayEpisodeList {
  struct Section {
    let title: String
    let episodes: [CarPlayEpisodeRow]
  }

  @DynamicInjected(\.imagePipeline) private var imagePipeline
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.userSettings) private var userSettings
  @DynamicInjected(\.carPlayListLimits) private var limits
  private static let log = Log.as("CarPlayEpisodeList")
  let template: CPListTemplate
  private let selection: CarPlaySelection
  private var sections: [Section] = []
  private var page = 0
  private var restricted = false
  private var rows: [Episode.ID: CPListItem] = [:]
  private var imageURLs: [Episode.ID: URL] = [:]
  private var artworkTasks: [Episode.ID: Task<Void, Never>] = [:]
  private var navigationRows: [CPListItem] = []
  private var leadingItems: [CPListItem] = []
  private let listeningState: Bool
  private var emptyTitle = "Your queue is empty"
  private var emptySubtitle = "Add episodes to Up Next in PodHaven."
  private var artworkEnabled = true

  init(template: CPListTemplate, selection: CarPlaySelection, listeningState: Bool = false) {
    self.template = template
    self.selection = selection
    self.listeningState = listeningState
    template.emptyViewTitleVariants = ["Your queue is empty"]
    template.emptyViewSubtitleVariants = ["Add episodes to Up Next in PodHaven."]
  }

  func update(
    _ sections: [Section],
    restricted: Bool,
    leading: [CPListItem] = [],
    emptyTitle: String = "Your queue is empty",
    emptySubtitle: String = "Add episodes to Up Next in PodHaven."
  ) {
    for item in leadingItems where !leading.contains(where: { $0 === item }) { item.handler = nil }
    leadingItems = leading
    self.emptyTitle = emptyTitle
    self.emptySubtitle = emptySubtitle
    self.sections = sections
    self.restricted = restricted
    render()
  }

  private func render() {
    let limits = limits()
    let all = sections.flatMap { section in section.episodes.map { (section.title, $0) } }
    let slice = CarPlayPage(
      count: all.count,
      page: page,
      limits: limits,
      restricted: restricted,
      leading: leadingItems.count
    )
    if slice.limited && slice.range.isEmpty {
      template.emptyViewTitleVariants = ["List unavailable"]
      template.emptyViewSubtitleVariants = ["Content is limited by the vehicle."]
    } else {
      template.emptyViewTitleVariants = [emptyTitle]
      template.emptyViewSubtitleVariants = [emptySubtitle]
    }
    page = slice.index
    let visible = Array(all[slice.range])
    let visibleIDs = Set(visible.map { $0.1.id })
    for (id, item) in rows where !visibleIDs.contains(id) {
      item.handler = nil
      artworkTasks.removeValue(forKey: id)?.cancel()
      imageURLs.removeValue(forKey: id)
    }
    rows = rows.filter { visibleIDs.contains($0.key) }
    for item in navigationRows { item.handler = nil }
    navigationRows = []
    var groups: [(String, [CPListItem])] = []
    if slice.leadingCount > 0 {
      groups.append(("", Array(leadingItems.prefix(slice.leadingCount))))
    }
    for (title, episode) in visible {
      let item = rows[episode.id] ?? CPListItem(text: episode.title, detailText: nil)
      rows[episode.id] = item
      item.userInfo = episode.id
      item.setText(episode.title)
      let current = sharedState.currentEpisodeID == episode.id
      var detail = episode.detail(
        remaining: userSettings.showTimeRemainingInEpisodeLists,
        current: current,
        listeningState: listeningState
      )
      if slice.limited, episode.id == visible.last?.1.id {
        detail += " · More episodes available when vehicle limits permit."
      }
      item.setDetailText(detail)
      item.isPlaying = current && sharedState.playbackStatus.playing
      item.playingIndicatorLocation = .trailing
      let duration = episode.duration.seconds
      let progress =
        duration.isFinite && duration > 0 ? episode.currentTime.safe.seconds / duration : 0
      item.playbackProgress = CGFloat(min(1, max(0, progress)))
      item.handler = { [weak selection] _, completion in
        guard let selection else {
          completion()
          return
        }
        selection.select(episode.id, completion: completion)
      }
      if artworkEnabled, imageURLs[episode.id] != episode.image {
        artworkTasks.removeValue(forKey: episode.id)?.cancel()
        imageURLs[episode.id] = episode.image
        item.setImage(nil)
        artworkTasks[episode.id] = Task { [weak self, weak item, imagePipeline] in
          do {
            let image = try await imagePipeline.image(for: episode.image)
            guard !Task.isCancelled, let self, let item,
              self.rows[episode.id] === item, self.imageURLs[episode.id] == episode.image
            else { return }
            item.setImage(image)
          } catch {
            Self.log.caughtError("CarPlay artwork unavailable: episode=\(episode.id)", error)
          }
        }
      }
      if groups.last?.0 == title {
        groups[groups.count - 1].1.append(item)
      } else {
        groups.append((title, [item]))
      }
    }
    if slice.canPage {
      var navigation: [CPListItem] = []
      for (title, target) in slice.controls {
        let item = CPListItem(text: title, detailText: "Page \(target + 1) of \(slice.last + 1)")
        item.handler = { [weak self, weak item] _, completion in
          completion()
          guard let self, let item, self.navigationRows.contains(where: { $0 === item }) else {
            return
          }
          self.page = target
          self.render()
        }
        navigation.append(item)
      }
      navigationRows = navigation
      groups.append(("Pages", navigation))
    }
    if groups.count > max(0, limits.sections) {
      groups = limits.sections > 0 ? [("", groups.flatMap(\.1))] : []
    }
    template.updateSections(
      groups.map { CPListSection(items: $0.1, header: $0.0, sectionIndexTitle: nil) }
    )
  }

  func setArtworkEnabled(_ enabled: Bool) {
    guard artworkEnabled != enabled else { return }
    artworkEnabled = enabled
    if enabled { render() } else { cancelArtwork() }
  }

  private func cancelArtwork() {
    for task in artworkTasks.values { task.cancel() }
    artworkTasks = [:]
    imageURLs = [:]
  }

  func resetPage() { page = 0 }

  func stop() {
    cancelArtwork()
    for item in rows.values { item.handler = nil }
    for item in navigationRows { item.handler = nil }
    for item in leadingItems { item.handler = nil }
    rows = [:]
    navigationRows = []
    leadingItems = []
  }
}

#if DEBUG
private struct CarPlayEpisodePreview: View {
  let empty: Bool
  var body: some View {
    if empty {
      ContentUnavailableView(
        "Your queue is empty",
        systemImage: AppIcon.upNext.systemImageName,
        description: Text("Add episodes to Up Next in PodHaven.")
      )
    } else {
      List {
        Section("Current episode") {
          VStack(alignment: .leading) {
            Text("An episode in progress")
            Text("Example podcast · 24m remaining · Current episode · Downloaded").font(.caption)
            ProgressView(value: 0.4)
          }
        }
        Section("Up Next") {
          Text("Another episode")
          Text("Loading episode…")
        }
        Section("Recommended") { Text("A recommended episode") }
        Button("Next page") {}
        Text("Couldn't play this episode. Try again.")
      }
    }
  }
}
#Preview("CarPlay episode content") { CarPlayEpisodePreview(empty: false) }
#Preview("CarPlay empty queue") { CarPlayEpisodePreview(empty: true) }
#endif
