// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Logging

@MainActor protocol ManagingEpisodes: AnyObject {
  associatedtype EpisodeType: EpisodeListable

  func isEpisodePlaying(_ episode: EpisodeType) -> Bool
  func isEpisodeAtBottomOfQueue(_ episode: EpisodeType) -> Bool
  func canClearCache(_ episode: EpisodeType) -> Bool

  func playEpisode(_ episode: EpisodeType)
  func pauseEpisode(_ episode: EpisodeType)
  func queueEpisodeOnTop(_ episode: EpisodeType, swipeAction: Bool)
  func queueEpisodeAtBottom(_ episode: EpisodeType, swipeAction: Bool)
  func removeEpisodeFromQueue(_ episode: EpisodeType)
  func cacheEpisode(_ episode: EpisodeType)
  func uncacheEpisode(_ episode: EpisodeType)
  func rateEpisode(_ episode: EpisodeType, rating: EpisodeRating?)
  func markEpisodeFinished(_ episode: EpisodeType)
  func applyTag(_ tagID: Tag.ID, to episode: EpisodeType)

  func getOrCreatePodcastEpisode(_ episode: EpisodeType) async throws -> PodcastEpisode
}

extension ManagingEpisodes {
  private var cacheManager: CacheManager { Container.shared.cacheManager() }
  private var playManager: PlayManager { Container.shared.playManager() }
  private var queue: any Queueing { Container.shared.queue() }
  private var repo: any Databasing { Container.shared.repo() }
  private var sharedState: SharedState { Container.shared.sharedState() }

  private var alert: Alert { Container.shared.alert() }

  nonisolated private static var log: Logger { Log.as(LogSubsystem.ViewProtocols.managingEpisode) }

  // MARK: - Getters

  func isEpisodePlaying(_ episode: EpisodeType) -> Bool {
    sharedState.isEpisodePlaying(episode)
  }

  func isEpisodeAtBottomOfQueue(_ episode: EpisodeType) -> Bool {
    guard let queueOrder = episode.queueOrder,
      let maxQueuePosition = sharedState.maxQueuePosition
    else { return false }
    return queueOrder == maxQueuePosition
  }

  func canClearCache(_ episode: EpisodeType) -> Bool {
    episode.cacheStatus != .uncached && CacheManager.canClearCache(episode)
  }

  // MARK: - Actions

  func playEpisode(_ episode: EpisodeType) {
    Task { [weak self] in
      guard let self else { return }

      do {
        let podcastEpisode = try await getOrCreatePodcastEpisode(episode)
        try await playManager.load(podcastEpisode)
        await playManager.play()
      } catch {
        Self.log.caughtError("playEpisode: failed for \(episode.title)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  func pauseEpisode(_ episode: EpisodeType) {
    guard isEpisodePlaying(episode) else { return }

    Task { [weak self] in
      guard let self else { return }

      await playManager.pause()
    }
  }

  func queueEpisodeOnTop(_ episode: EpisodeType, swipeAction: Bool = false) {
    guard episode.queueOrder != 0 else { return }

    Task { [weak self] in
      guard let self else { return }

      do {
        let episodeID = try await getOrCreateEpisodeID(episode)
        try await queue.unshift(episodeID)
      } catch {
        Self.log.caughtError("queueEpisodeOnTop: failed for \(episode.title)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  func queueEpisodeAtBottom(_ episode: EpisodeType, swipeAction: Bool = false) {
    guard !isEpisodeAtBottomOfQueue(episode) else { return }

    Task { [weak self] in
      guard let self else { return }

      do {
        let episodeID = try await getOrCreateEpisodeID(episode)
        try await queue.append(episodeID)
      } catch {
        Self.log.caughtError("queueEpisodeAtBottom: failed for \(episode.title)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  func removeEpisodeFromQueue(_ episode: EpisodeType) {
    guard episode.queued else { return }

    Task { [weak self] in
      guard let self else { return }

      do {
        let episodeID = try await getOrCreateEpisodeID(episode)
        try await queue.dequeue(episodeID)
      } catch {
        Self.log.caughtError("removeEpisodeFromQueue: failed for \(episode.title)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  func cacheEpisode(_ episode: EpisodeType) {
    Task { [weak self] in
      guard let self else { return }

      do {
        let episodeID = try await getOrCreateEpisodeID(episode)
        try await cacheManager.downloadToCache(for: episodeID)
      } catch {
        Self.log.caughtError("cacheEpisode: failed for \(episode.title)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  func uncacheEpisode(_ episode: EpisodeType) {
    guard canClearCache(episode) else { return }

    Task { [weak self] in
      guard let self else { return }

      let episodeID: Episode.ID
      do {
        episodeID = try await getOrCreateEpisodeID(episode)
      } catch {
        Self.log.caughtError("uncacheEpisode: failed to get/create episode \(episode.title)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
        return
      }

      do {
        try await repo.updateSaveInCache(episodeID, saveInCache: false)
      } catch {
        Self.log.caughtError("uncacheEpisode: failed to unsave episode \(episode.title)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }

      do {
        try await cacheManager.clearCache(for: episodeID)
      } catch {
        Self.log.caughtError("uncacheEpisode: failed to clear cache for \(episode.title)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  func saveEpisodeInCache(_ episode: EpisodeType) {
    Task { [weak self] in
      guard let self else { return }

      let episodeID: Episode.ID
      do {
        episodeID = try await getOrCreateEpisodeID(episode)
      } catch {
        Self.log.caughtError(
          "saveEpisodeInCache: failed to get/create episode \(episode.title)",
          error
        )
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
        return
      }

      do {
        try await repo.updateSaveInCache(episodeID, saveInCache: true)
      } catch {
        Self.log.caughtError("saveEpisodeInCache: failed to save episode \(episode.title)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
        return
      }

      do {
        try await cacheManager.downloadToCache(for: episodeID)
      } catch {
        Self.log.caughtError("saveEpisodeInCache: failed to cache episode \(episode.title)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  func unsaveEpisodeFromCache(_ episode: EpisodeType) {
    guard episode.saveInCache else { return }

    Task { [weak self] in
      guard let self else { return }

      do {
        let episodeID = try await getOrCreateEpisodeID(episode)
        try await repo.updateSaveInCache(episodeID, saveInCache: false)
      } catch {
        Self.log.caughtError("unsaveEpisodeFromCache: failed for \(episode.title)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  func markEpisodeFinished(_ episode: EpisodeType) {
    guard !episode.finished else { return }

    Task { [weak self] in
      guard let self else { return }

      do {
        let episodeID = try await getOrCreateEpisodeID(episode)
        try await repo.markFinished(episodeID)
      } catch {
        Self.log.caughtError("markEpisodeFinished: failed for \(episode.title)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  func rateEpisode(_ episode: EpisodeType, rating: EpisodeRating?) {
    guard episode.rating != rating else { return }

    Task { [weak self] in
      guard let self else { return }

      do {
        let episodeID = try await getOrCreateEpisodeID(episode)
        try await repo.updateRating(episodeID, rating: rating)
      } catch {
        Self.log.caughtError("rateEpisode: failed for \(episode.title)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  func applyTag(_ tagID: Tag.ID, to episode: EpisodeType) {
    Task { [weak self] in
      guard let self else { return }

      do {
        let episodeID = try await getOrCreateEpisodeID(episode)
        try await repo.addTag(tagID, to: episodeID)
      } catch {
        Self.log.caughtError(
          "applyTag: failed to apply tag \(tagID) to \(episode.title)",
          error
        )
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  // MARK: - Helpers

  private func getOrCreateEpisodeID(_ episode: EpisodeType) async throws -> Episode.ID {
    try await getOrCreatePodcastEpisode(episode).id
  }
}

extension ManagingEpisodes where EpisodeType == PodcastEpisode {
  func getOrCreatePodcastEpisode(_ episode: PodcastEpisode) async throws -> PodcastEpisode {
    episode
  }
}

extension ManagingEpisodes where EpisodeType == ListablePodcastEpisode {
  func getOrCreatePodcastEpisode(_ episode: ListablePodcastEpisode) async throws -> PodcastEpisode {
    try await episode.getPodcastEpisode()
  }
}
