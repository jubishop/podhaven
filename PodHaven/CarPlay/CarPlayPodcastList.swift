// Copyright Justin Bishop, 2026

import CarPlay
import FactoryKit
import Foundation
import Logging
import Nuke

@MainActor
final class CarPlayPodcastList {
  typealias Entry = PodcastWithEpisodeMetadata<ListablePodcast>
  @DynamicInjected(\.imagePipeline) private var imagePipeline
  @DynamicInjected(\.carPlayListLimits) private var limits
  private static let log = Log.as("CarPlayPodcastList")
  let template: CPListTemplate
  private let select: (Podcast.ID) -> Void
  private var entries: [Entry] = []
  private var leading: [CPListItem] = []
  private var rows: [Podcast.ID: CPListItem] = [:]
  private var imageURLs: [Podcast.ID: URL] = [:]
  private var artwork: [Podcast.ID: Task<Void, Never>] = [:]
  private var controls: [CPListItem] = []
  private var page = 0
  private var restricted = false
  private var header = ""
  private var artworkEnabled = true

  init(template: CPListTemplate, select: @escaping (Podcast.ID) -> Void) {
    self.template = template
    self.select = select
  }

  func update(_ entries: [Entry], header: String = "", leading: [CPListItem] = [], restricted: Bool)
  {
    for item in self.leading where !leading.contains(where: { $0 === item }) { item.handler = nil }
    self.entries = entries
    self.leading = leading
    self.header = header
    self.restricted = restricted
    render()
  }

  private func render() {
    let limits = limits()
    let slice = CarPlayPage(
      count: entries.count,
      page: page,
      limits: limits,
      restricted: restricted,
      leading: leading.count
    )
    page = slice.index
    let visible = Array(entries[slice.range])
    let ids = Set(visible.map { $0.podcast.id })
    for (id, row) in rows where !ids.contains(id) {
      row.handler = nil
      artwork.removeValue(forKey: id)?.cancel()
      imageURLs.removeValue(forKey: id)
    }
    rows = rows.filter { ids.contains($0.key) }
    for control in controls { control.handler = nil }
    controls = []
    var items = Array(leading.prefix(slice.leadingCount))
    for entry in visible {
      let podcast = entry.podcast
      let row = rows[podcast.id] ?? CPListItem(text: podcast.title, detailText: nil)
      rows[podcast.id] = row
      row.userInfo = podcast.id
      row.setText(podcast.title)
      var detail =
        entry.episodeCount == 0 ? "No saved episodes" : "\(entry.episodeCount) saved episodes"
      if let date = entry.mostRecentEpisodeDate {
        detail += " · \(date.formatted(date: .abbreviated, time: .omitted))"
      }
      if slice.limited, podcast.id == visible.last?.podcast.id {
        detail += " · More podcasts available when vehicle limits permit."
      }
      row.setDetailText(detail)
      row.accessoryType = .disclosureIndicator
      row.handler = { [weak self, weak row] _, completion in
        completion()
        guard let self, let row, self.rows[podcast.id] === row else { return }
        self.select(podcast.id)
      }
      if artworkEnabled, imageURLs[podcast.id] != podcast.image {
        artwork.removeValue(forKey: podcast.id)?.cancel()
        imageURLs[podcast.id] = podcast.image
        row.setImage(nil)
        artwork[podcast.id] = Task { [weak self, weak row, imagePipeline] in
          do {
            let image = try await imagePipeline.image(for: podcast.image)
            guard !Task.isCancelled, let self, let row,
              self.rows[podcast.id] === row, self.imageURLs[podcast.id] == podcast.image
            else { return }
            row.setImage(image)
          } catch {
            Self.log.caughtError(
              "CarPlay podcast artwork unavailable: podcast=\(podcast.id)",
              error
            )
          }
        }
      }
      items.append(row)
    }
    for (title, target) in slice.controls {
      let row = CPListItem(text: title, detailText: "Page \(target + 1) of \(slice.last + 1)")
      row.handler = { [weak self, weak row] _, completion in
        completion()
        guard let self, let row, self.controls.contains(where: { $0 === row }) else { return }
        self.page = target
        self.render()
      }
      controls.append(row)
      items.append(row)
    }
    if slice.limited, visible.isEmpty {
      template.emptyViewTitleVariants = ["List unavailable"]
      template.emptyViewSubtitleVariants = ["Content is limited by the vehicle."]
    }
    template.updateSections(
      items.isEmpty ? [] : [CPListSection(items: items, header: header, sectionIndexTitle: nil)]
    )
  }

  func setArtworkEnabled(_ enabled: Bool) {
    guard artworkEnabled != enabled else { return }
    artworkEnabled = enabled
    if enabled { render() } else { cancelArtwork() }
  }

  private func cancelArtwork() {
    for task in artwork.values { task.cancel() }
    artwork = [:]
    imageURLs = [:]
  }

  func stop() {
    cancelArtwork()
    for item in rows.values { item.handler = nil }
    for item in controls + leading { item.handler = nil }
    rows = [:]
    controls = []
    leading = []
  }
}
