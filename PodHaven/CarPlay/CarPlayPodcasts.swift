// Copyright Justin Bishop, 2026

import CarPlay
import FactoryKit
import Foundation
import GRDB
import Logging

extension Container {
  @MainActor var carPlayPodcasts: Factory<CarPlayPodcasts> {
    Factory(self) { CarPlayPodcasts() }
  }
}

@MainActor
final class CarPlayPodcasts {
  private enum Catalog {
    case loading
    case ready([CarPlayPodcastList.Entry])
    case failed
  }

  @MainActor private final class Detail {
    enum Mode { case unfinished, all }
    enum State {
      case loading
      case ready(PodcastSeriesDetail)
      case missing, failed
    }
    let id: Podcast.ID
    let list: CarPlayEpisodeList
    let shortcutEpisodeID: Episode.ID?
    var state = State.loading
    var mode = Mode.unfinished
    var observation: Task<Void, Never>?
    let filter = CPListItem(text: "All Episodes", detailText: "Include finished episodes")

    init(_ id: Podcast.ID, selection: CarPlaySelection, shortcutEpisodeID: Episode.ID?) {
      self.id = id
      self.shortcutEpisodeID = shortcutEpisodeID
      list = CarPlayEpisodeList(
        template: CPListTemplate(title: "Episodes", sections: []),
        selection: selection,
        listeningState: true
      )
    }

    func stop() {
      observation?.cancel()
      observation = nil
      filter.handler = nil
      list.stop()
    }
  }

  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.userSettings) private var userSettings
  @DynamicInjected(\.carPlayNowPlaying) private var nowPlaying
  private static let log = Log.as("CarPlayPodcasts")
  private var catalog = Catalog.loading
  private var root: CarPlayPodcastList?
  private var all: CarPlayPodcastList?
  private var detail: Detail?
  private var selection: CarPlaySelection?
  private var catalogObservation: Task<Void, Never>?
  private var stateObservation: Task<Void, Never>?
  private var currentObservation: Task<Void, Never>?
  private var shortcut: Task<Void, Never>?
  private let allPodcasts = CPListItem(text: "All Podcasts", detailText: "Browse subscribed shows")
  var navigate: ((CPListTemplate, Bool) -> Void)?
  var canNavigate: (() -> Bool)?
  var showError: ((String) -> Void)?
  var restricted = false {
    didSet {
      renderCatalog()
      renderDetail()
    }
  }

  fileprivate init() {}

  func start(_ template: CPListTemplate, selection: CarPlaySelection) {
    self.selection = selection
    root = CarPlayPodcastList(template: template) { [weak self] id in self?.openPodcast(id) }
    allPodcasts.accessoryType = .disclosureIndicator
    observeCatalog()
    stateObservation = Task { [weak self] in
      guard let self else { return }
      await withDiscardingTaskGroup { group in
        group.addTask { await self.observeCurrentID() }
        group.addTask { await self.observePlayback() }
        group.addTask { await self.observeOnDeck() }
        group.addTask { await self.observeTimeFormat() }
      }
    }
  }

  private func observeCatalog() {
    guard selection != nil else { return }
    catalogObservation?.cancel()
    catalog = .loading
    renderCatalog()
    catalogObservation = Task { [weak self] in
      guard let self else { return }
      do {
        for try await podcasts in observatory.listablePodcastsWithEpisodeMetadata({
          $0.subscribed()
        }) {
          guard !Task.isCancelled else { return }
          catalog = .ready(podcasts)
          renderCatalog()
        }
      } catch {
        Self.log.caughtError("CarPlay subscribed podcast observation failed", error)
        guard !Task.isCancelled else { return }
        catalog = .failed
        renderCatalog()
      }
    }
  }

  private func renderCatalog() {
    for list in [root, all].compactMap({ $0 }) {
      switch catalog {
      case .loading:
        list.template.showsSpinnerWhileEmpty = true
        list.template.emptyViewTitleVariants = ["Loading podcasts…"]
        list.template.emptyViewSubtitleVariants = ["Reading saved subscriptions."]
        list.update([], restricted: restricted)
      case .failed:
        list.template.showsSpinnerWhileEmpty = false
        let retry = CPListItem(text: "Retry", detailText: "Couldn't load podcasts.")
        retry.handler = { [weak self] _, completion in
          completion()
          self?.observeCatalog()
        }
        list.template.emptyViewTitleVariants = ["Couldn't load podcasts"]
        list.template.emptyViewSubtitleVariants = ["Try again when available."]
        list.update([], leading: [retry], restricted: restricted)
      case .ready(let podcasts):
        list.template.showsSpinnerWhileEmpty = false
        list.template.emptyViewTitleVariants = ["No subscriptions"]
        list.template.emptyViewSubtitleVariants = ["Your saved subscriptions appear here."]
        if list === root {
          allPodcasts.handler = { [weak self] _, completion in
            completion()
            self?.openAll()
          }
          let recent = podcasts.filter { $0.mostRecentEpisodeDate != nil }
            .sorted { lhs, rhs in
              if lhs.mostRecentEpisodeDate != rhs.mostRecentEpisodeDate {
                return (lhs.mostRecentEpisodeDate ?? .distantPast)
                  > (rhs.mostRecentEpisodeDate ?? .distantPast)
              }
              return lhs.podcast.id < rhs.podcast.id
            }
          list.update(
            Array(recent.prefix(10)),
            header: "Recently Updated",
            leading: podcasts.isEmpty ? [] : [allPodcasts],
            restricted: restricted
          )
        } else {
          let alphabetical = podcasts.sorted { lhs, rhs in
            let order = lhs.title.localizedStandardCompare(rhs.title)
            return order == .orderedSame
              ? lhs.podcast.id < rhs.podcast.id : order == .orderedAscending
          }
          list.update(alphabetical, restricted: restricted)
        }
      }
    }
  }

  private func openAll() {
    guard canNavigate?() == true else { return }
    all?.stop()
    let list = CarPlayPodcastList(template: CPListTemplate(title: "All Podcasts", sections: [])) {
      [weak self] id in self?.openPodcast(id)
    }
    all = list
    renderCatalog()
    navigate?(list.template, false)
  }

  private func openPodcast(_ id: Podcast.ID, shortcutEpisodeID: Episode.ID? = nil) {
    guard let selection, canNavigate?() == true else { return }
    selection.cancel()
    detail?.stop()
    let detail = Detail(id, selection: selection, shortcutEpisodeID: shortcutEpisodeID)
    self.detail = detail
    detail.filter.accessoryType = .disclosureIndicator
    observeDetail(detail)
    navigate?(detail.list.template, shortcutEpisodeID != nil)
  }

  private func observeDetail(_ detail: Detail) {
    detail.observation?.cancel()
    detail.state = .loading
    renderDetail()
    detail.observation = Task { [weak self, weak detail] in
      guard let self, let detail else { return }
      do {
        for try await series in observatory.podcastSeriesDetail(detail.id) {
          guard !Task.isCancelled, self.detail === detail else { return }
          if let series { detail.state = .ready(series) } else { detail.state = .missing }
          renderDetail()
        }
      } catch {
        Self.log.caughtError(
          "CarPlay podcast episode observation failed: podcast=\(detail.id)",
          error
        )
        guard !Task.isCancelled, self.detail === detail else { return }
        detail.state = .failed
        renderDetail()
      }
    }
  }

  private func renderDetail() {
    guard let detail else { return }
    detail.list.template.showsSpinnerWhileEmpty = false
    var rows: [CarPlayEpisodeRow] = []
    var leading: [CPListItem] = []
    let title: String
    let subtitle: String
    var header = ""
    switch detail.state {
    case .loading:
      detail.list.template.showsSpinnerWhileEmpty = true
      title = "Loading episodes…"
      subtitle = "Reading saved episodes."
    case .missing:
      title = "Podcast unavailable"
      subtitle = "This podcast is no longer saved."
    case .failed:
      title = "Couldn't load episodes"
      subtitle = "Try again."
      let retry = CPListItem(text: "Retry", detailText: title)
      retry.handler = { [weak self, weak detail] _, completion in
        completion()
        guard let self, let detail, self.detail === detail else { return }
        self.observeDetail(detail)
      }
      leading = [retry]
    case .ready(let series):
      detail.filter.handler = { [weak self, weak detail] _, completion in
        completion()
        guard let self, let detail, self.detail === detail else { return }
        self.selection?.cancel()
        detail.mode = detail.mode == .unfinished ? .all : .unfinished
        detail.list.resetPage()
        self.renderDetail()
      }
      let all = detail.mode == .all
      header = "\(series.podcast.title) · \(all ? "All Episodes" : "Unfinished")"
      let episodes = series.episodes.filter { all || !$0.finished }
        .sorted { lhs, rhs in
          lhs.pubDate == rhs.pubDate ? lhs.id < rhs.id : lhs.pubDate > rhs.pubDate
        }
      rows = episodes.map { episode in
        CarPlayEpisodeRow(ListablePodcastEpisode(podcast: series.podcast, episode: episode))
      }
      title = series.episodes.isEmpty ? "No saved episodes" : "No unfinished episodes"
      subtitle =
        series.episodes.isEmpty
        ? "Only saved episodes appear here." : "All saved episodes are finished."
      detail.filter.setText(all ? "Unfinished" : "All Episodes")
      detail.filter.setDetailText(all ? "Hide finished episodes" : "Include finished episodes")
      leading = [detail.filter]
      if rows.isEmpty {
        let empty = CPListItem(text: title, detailText: subtitle)
        empty.isEnabled = false
        leading.append(empty)
      }
    }
    detail.list.update(
      rows.isEmpty ? [] : [.init(title: header, episodes: rows)],
      restricted: restricted,
      leading: leading,
      emptyTitle: title,
      emptySubtitle: subtitle
    )
  }

  private func observeCurrentID() async {
    for await id in sharedState.$currentEpisodeID.stream() {
      guard !Task.isCancelled else { return }
      currentObservation?.cancel()
      nowPlaying.isAlbumArtistButtonEnabled = false
      renderDetail()
      guard let id else { continue }
      currentObservation = Task { [weak self] in
        guard let self else { return }
        do {
          for try await episode in observatory.podcastEpisodeWithTags(id) {
            guard !Task.isCancelled, sharedState.currentEpisodeID == id else { return }
            nowPlaying.isAlbumArtistButtonEnabled = episode != nil
          }
        } catch {
          Self.log.caughtError("CarPlay current podcast observation failed: episode=\(id)", error)
        }
      }
    }
  }

  private func observePlayback() async {
    for await _ in sharedState.$playbackStatus.stream() {
      guard !Task.isCancelled else { return }
      renderDetail()
    }
  }

  private func observeOnDeck() async {
    for await _ in sharedState.$onDeck.stream() {
      guard !Task.isCancelled else { return }
      renderDetail()
    }
  }

  private func observeTimeFormat() async {
    for await _ in userSettings.$showTimeRemainingInEpisodeLists.stream() {
      guard !Task.isCancelled else { return }
      renderDetail()
    }
  }

  func openCurrentPodcast() {
    shortcut?.cancel()
    guard let id = sharedState.currentEpisodeID, selection != nil, canNavigate?() == true else {
      return
    }
    shortcut = Task { [weak self] in
      guard let self else { return }
      do {
        let episode = try await repo.podcastEpisode(id)
        guard !Task.isCancelled, selection != nil, sharedState.currentEpisodeID == id else {
          return
        }
        guard let episode else {
          nowPlaying.isAlbumArtistButtonEnabled = false
          showError?("This podcast is no longer available.")
          return
        }
        openPodcast(episode.podcast.id, shortcutEpisodeID: id)
      } catch {
        Self.log.caughtError("CarPlay current podcast lookup failed: episode=\(id)", error)
        guard !Task.isCancelled, sharedState.currentEpisodeID == id else { return }
        showError?("Couldn't open this podcast. Try again.")
      }
    }
  }

  func canOpen(_ template: CPTemplate) -> Bool {
    if let detail, detail.list.template === template {
      if let id = detail.shortcutEpisodeID { return sharedState.currentEpisodeID == id }
      return true
    }
    return all?.template === template
  }

  func navigationChanged(templates: [CPTemplate], rootVisible: Bool) {
    shortcut?.cancel()
    shortcut = nil
    if let detail, !templates.contains(where: { $0 === detail.list.template }) {
      selection?.cancel()
      detail.stop()
      self.detail = nil
    }
    if let all, !templates.contains(where: { $0 === all.template }) {
      all.stop()
      self.all = nil
    }
    root?.setArtworkEnabled(templates.count == 1 && rootVisible)
    all?.setArtworkEnabled(templates.last === all?.template)
    detail?.list.setArtworkEnabled(templates.last === detail?.list.template)
  }

  func stop() {
    catalogObservation?.cancel()
    stateObservation?.cancel()
    currentObservation?.cancel()
    shortcut?.cancel()
    catalogObservation = nil
    stateObservation = nil
    currentObservation = nil
    shortcut = nil
    root?.stop()
    all?.stop()
    detail?.stop()
    root = nil
    all = nil
    detail = nil
    selection = nil
    allPodcasts.handler = nil
    navigate = nil
    canNavigate = nil
    showError = nil
  }
}
