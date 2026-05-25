// Copyright Justin Bishop, 2026

import FactoryKit
import Logging
import SwiftUI

// Thin wrapper around the collector that adapts ManagingEpisodes to remove
// each pick after the underlying action succeeds. The protocol's default
// implementations are fire-and-forget Tasks, so each overridden method
// reruns the materialize → action → removePick sequence here.
@Observable @MainActor
final class SearchDiscoveryActionsViewModel: ManagingEpisodes {
  typealias EpisodeType = ListedEpisode

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
    performAfterMaterialize(episode, context: "playEpisode") { [playManager] podcastEpisode in
      try await playManager.load(podcastEpisode)
      await playManager.play()
    }
  }

  func queueEpisodeOnTop(_ episode: ListedEpisode, swipeAction: Bool = false) {
    guard episode.queueOrder != 0 else { return }
    performAfterMaterialize(episode, context: "queueEpisodeOnTop") { [queue] podcastEpisode in
      try await queue.unshift(podcastEpisode.id)
    }
  }

  func queueEpisodeAtBottom(_ episode: ListedEpisode, swipeAction: Bool = false) {
    performAfterMaterialize(episode, context: "queueEpisodeAtBottom") { [queue] podcastEpisode in
      try await queue.append(podcastEpisode.id)
    }
  }

  func cacheEpisode(_ episode: ListedEpisode) {
    performAfterMaterialize(episode, context: "cacheEpisode") { [cacheManager] podcastEpisode in
      try await cacheManager.downloadToCache(for: podcastEpisode.id)
    }
  }

  func saveEpisodeInCache(_ episode: ListedEpisode) {
    performAfterMaterialize(episode, context: "saveEpisodeInCache") {
      [cacheManager, repo] podcastEpisode in
      _ = try await repo.updateSaveInCache(podcastEpisode.id, saveInCache: true)
      try await cacheManager.downloadToCache(for: podcastEpisode.id)
    }
  }

  func rateEpisode(_ episode: ListedEpisode, rating: EpisodeRating?) {
    guard episode.rating != rating else { return }
    performAfterMaterialize(episode, context: "rateEpisode") { [repo] podcastEpisode in
      _ = try await repo.updateRating(podcastEpisode.id, rating: rating)
    }
  }

  func markEpisodeFinished(_ episode: ListedEpisode) {
    guard !episode.finished else { return }
    performAfterMaterialize(episode, context: "markEpisodeFinished") { [repo] podcastEpisode in
      _ = try await repo.markFinished(podcastEpisode.id)
    }
  }

  private func performAfterMaterialize(
    _ episode: ListedEpisode,
    context: String,
    perform: @escaping @Sendable (PodcastEpisode) async throws -> Void
  ) {
    Task { [weak self] in
      guard let self else { return }
      do {
        let podcastEpisode = try await episode.getOrCreatePodcastEpisode()
        try await perform(podcastEpisode)
        self.collector?.removePick(feedURL: episode.feedURL, mediaGUID: episode.mediaGUID)
      } catch {
        Self.log.caughtError("\(context): failed for \(episode.title)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        Container.shared.alert()(ErrorKit.message(for: error))
      }
    }
  }
}
