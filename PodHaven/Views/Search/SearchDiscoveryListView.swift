// Copyright Justin Bishop, 2026

import FactoryKit
import Logging
import SwiftUI

// MARK: - Environment

private struct SearchRecommendationCollectorKey: EnvironmentKey {
  static let defaultValue: SearchRecommendationCollector? = nil
}

extension EnvironmentValues {
  // SearchView sets this so the pushed discovery list reads the active
  // source's scored picks without re-instantiating its own collector.
  var searchRecommendationCollector: SearchRecommendationCollector? {
    get { self[SearchRecommendationCollectorKey.self] }
    set { self[SearchRecommendationCollectorKey.self] = newValue }
  }
}

// MARK: - View

struct SearchDiscoveryListView: View {
  @Environment(\.searchRecommendationCollector) private var collector
  @DynamicInjected(\.navigation) private var navigation

  private let source: SearchRecommendationCollector.Source

  init(source: SearchRecommendationCollector.Source) {
    self.source = source
  }

  var body: some View {
    Group {
      if let collector {
        if collector.visiblePicks.isEmpty {
          emptyPlaceholder
        } else {
          listView(picks: collector.visiblePicks, collector: collector)
        }
      } else {
        emptyPlaceholder
      }
    }
    .navigationTitle(source.discoveryListTitle)
    .toolbarRole(.editor)
  }

  // MARK: - List

  private func listView(
    picks: [SearchRecommendationCollector.ScoredEpisode],
    collector: SearchRecommendationCollector
  ) -> some View {
    let viewModel = SearchDiscoveryActionsViewModel(collector: collector)
    return List(picks) { pick in
      let listed = ListedEpisode(pick.episode)
      NavigationLink(
        value: Navigation.Destination.listedEpisode(listed),
        label: {
          EpisodeListView(episode: listed)
            .listRowSeparator()
        }
      )
      .listRow()
      .episodeSwipeActions(viewModel: viewModel, episode: listed)
      .episodeContextMenu(viewModel: viewModel, episode: listed)
    }
    .animation(.default, value: picks)
  }

  // MARK: - Placeholder

  private var emptyPlaceholder: some View {
    VStack(spacing: 16) {
      AppIcon.search.image
        .font(.system(size: 48))
      Text("No top picks yet")
        .font(.headline)
      Text("Tap a result to dive deeper, then check back here.")
        .font(.subheadline)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

// MARK: - Actions View Model

// Thin wrapper around the collector that adapts ManagingEpisodes to remove
// each pick after the underlying action succeeds. The protocol's default
// implementations are fire-and-forget Tasks, so each overridden method
// reruns the materialize → action → removePick sequence here.
@Observable @MainActor
final class SearchDiscoveryActionsViewModel: ManagingEpisodes {
  typealias EpisodeType = ListedEpisode

  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.cacheManager) private var cacheManager
  @ObservationIgnored @DynamicInjected(\.playManager) private var playManager
  @ObservationIgnored @DynamicInjected(\.queue) private var queue
  @ObservationIgnored @DynamicInjected(\.repo) private var repo
  @ObservationIgnored @DynamicInjected(\.sharedState) private var sharedState

  nonisolated private static let log = Log.as(LogSubsystem.SearchView.recommendations)

  private weak var collector: SearchRecommendationCollector?

  init(collector: SearchRecommendationCollector) {
    self.collector = collector
  }

  // MARK: - Actions With Post-Removal

  func playEpisode(_ episode: ListedEpisode) {
    performAfterMaterialize(episode, context: "playEpisode") { [playManager] episodeID in
      let podcastEpisode = try await Container.shared.repo().podcastEpisode(episodeID)
      guard let podcastEpisode else { return }
      try await playManager.load(podcastEpisode)
      await playManager.play()
    }
  }

  func queueEpisodeOnTop(_ episode: ListedEpisode, swipeAction: Bool = false) {
    guard episode.queueOrder != 0 else { return }
    performAfterMaterialize(episode, context: "queueEpisodeOnTop") { [queue] episodeID in
      try await queue.unshift(episodeID)
    }
  }

  func queueEpisodeAtBottom(_ episode: ListedEpisode, swipeAction: Bool = false) {
    performAfterMaterialize(episode, context: "queueEpisodeAtBottom") { [queue] episodeID in
      try await queue.append(episodeID)
    }
  }

  func cacheEpisode(_ episode: ListedEpisode) {
    performAfterMaterialize(episode, context: "cacheEpisode") { [cacheManager] episodeID in
      try await cacheManager.downloadToCache(for: episodeID)
    }
  }

  func saveEpisodeInCache(_ episode: ListedEpisode) {
    performAfterMaterialize(episode, context: "saveEpisodeInCache") {
      [cacheManager, repo] episodeID in
      _ = try await repo.updateSaveInCache(episodeID, saveInCache: true)
      try await cacheManager.downloadToCache(for: episodeID)
    }
  }

  func rateEpisode(_ episode: ListedEpisode, rating: EpisodeRating?) {
    guard episode.rating != rating else { return }
    performAfterMaterialize(episode, context: "rateEpisode") { [repo] episodeID in
      _ = try await repo.updateRating(episodeID, rating: rating)
    }
  }

  func markEpisodeFinished(_ episode: ListedEpisode) {
    guard !episode.finished else { return }
    performAfterMaterialize(episode, context: "markEpisodeFinished") { [repo] episodeID in
      _ = try await repo.markFinished(episodeID)
    }
  }

  private func performAfterMaterialize(
    _ episode: ListedEpisode,
    context: String,
    perform: @escaping @Sendable (Episode.ID) async throws -> Void
  ) {
    let collector = collector
    let alertProxy = alert
    let mediaGUID = episode.mediaGUID
    Task {
      do {
        let podcastEpisode = try await episode.getOrCreatePodcastEpisode()
        try await perform(podcastEpisode.id)
        collector?.removePick(mediaGUID: mediaGUID)
      } catch {
        Self.log.caughtError("\(context): failed for \(episode.title)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alertProxy(ErrorKit.message(for: error))
      }
    }
  }
}
