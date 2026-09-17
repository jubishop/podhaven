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

  init(_ episode: ListablePodcastEpisode) {
    id = episode.id
    title = episode.title
    podcast = episode.podcastTitle
    image = episode.image
    duration = episode.duration
    currentTime = episode.currentTime
    downloaded = episode.cacheStatus == .cached
  }

  init(_ episode: OnDeck) {
    id = episode.id
    title = episode.title
    podcast = episode.podcastTitle
    image = episode.image
    duration = episode.duration
    currentTime = episode.currentTime
    downloaded = episode.cacheStatus == .cached
  }

  func detail(remaining: Bool, current: Bool) -> String {
    var parts = [podcast]
    if duration.seconds.isFinite, duration.seconds > 0 {
      let time =
        remaining ? CMTime.seconds(max(0, duration.seconds - currentTime.safe.seconds)) : duration
      parts.append(remaining ? "\(time.shortDescription) remaining" : time.shortDescription)
    }
    if current { parts.append("Current episode") }
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

  init(template: CPListTemplate, selection: CarPlaySelection) {
    self.template = template
    self.selection = selection
    template.emptyViewTitleVariants = ["Your queue is empty"]
    template.emptyViewSubtitleVariants = ["Add episodes to Up Next in PodHaven."]
  }

  func update(_ sections: [Section], restricted: Bool) {
    self.sections = sections
    self.restricted = restricted
    render()
  }

  private func render() {
    let limits = limits()
    let budget = max(0, min(50, limits.items))
    let all = sections.flatMap { section in section.episodes.map { (section.title, $0) } }
    if !all.isEmpty && (budget == 0 || limits.sections == 0) {
      template.emptyViewTitleVariants = ["List unavailable"]
      template.emptyViewSubtitleVariants = ["Content is limited by the vehicle."]
    } else {
      template.emptyViewTitleVariants = ["Your queue is empty"]
      template.emptyViewSubtitleVariants = ["Add episodes to Up Next in PodHaven."]
    }
    let canPage = !restricted && budget >= 3 && all.count > budget
    let capacity = canPage ? budget - 2 : max(1, budget)
    let lastPage = max(0, (all.count - 1) / capacity)
    page = canPage ? min(page, lastPage) : 0
    let visible = Array(
      all.dropFirst(page * capacity).prefix(limits.sections > 0 ? min(capacity, budget) : 0)
    )
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
    for (title, episode) in visible {
      let item = rows[episode.id] ?? CPListItem(text: episode.title, detailText: nil)
      rows[episode.id] = item
      item.setText(episode.title)
      let current = sharedState.currentEpisodeID == episode.id
      var detail = episode.detail(
        remaining: userSettings.showTimeRemainingInEpisodeLists,
        current: current
      )
      if !canPage, all.count > visible.count, episode.id == visible.last?.1.id {
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
      if imageURLs[episode.id] != episode.image {
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
    if canPage {
      var navigation: [CPListItem] = []
      for (title, target) in [("Previous page", page - 1), ("Next page", page + 1)]
      where target >= 0 && target <= lastPage {
        let item = CPListItem(text: title, detailText: "Page \(target + 1) of \(lastPage + 1)")
        item.handler = { [weak self] _, completion in
          completion()
          guard let self else { return }
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

  func stop() {
    for task in artworkTasks.values { task.cancel() }
    artworkTasks = [:]
    for item in rows.values { item.handler = nil }
    for item in navigationRows { item.handler = nil }
    rows = [:]
    navigationRows = []
    imageURLs = [:]
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
