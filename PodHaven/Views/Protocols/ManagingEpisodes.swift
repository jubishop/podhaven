// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Logging

@MainActor protocol ManagingEpisodes: AnyObject {
  associatedtype EpisodeType: EpisodeDisplayable

  func playEpisode(_ episode: EpisodeType)
  func pauseEpisode(_ episode: EpisodeType)
  func queueEpisodeOnTop(_ episode: EpisodeType, swipeAction: Bool)
  func queueEpisodeAtBottom(_ episode: EpisodeType, swipeAction: Bool)
  func removeEpisodeFromQueue(_ episode: EpisodeType)
  func cacheEpisode(_ episode: EpisodeType)
  func uncacheEpisode(_ episode: EpisodeType)
  func markEpisodeFinished(_ episode: EpisodeType)
  func showPodcast(_ episode: EpisodeType)

  func isEpisodePlaying(_ episode: EpisodeType) -> Bool
  func isEpisodeAtBottomOfQueue(_ episode: EpisodeType) -> Bool
  func canClearCache(_ episode: EpisodeType) -> Bool

  func getOrCreatePodcastEpisode(_ episode: EpisodeType) async throws -> PodcastEpisode
}

extension ManagingEpisodes {
  private var cacheManager: CacheManager { Container.shared.cacheManager() }
  private var repo: any Databasing { Container.shared.repo() }
  private var navigation: Navigation { Container.shared.navigation() }
  private var playManager: PlayManager { Container.shared.playManager() }
  private var playState: PlayState { Container.shared.playState() }
  private var queue: any Queueing { Container.shared.queue() }

  private var log: Logger { Log.as(LogSubsystem.ViewProtocols.managingEpisode) }

  func playEpisode(_ episode: EpisodeType) {
    Task { [weak self] in
      guard let self else { return }

      do {
        let podcastEpisode = try await getOrCreatePodcastEpisode(episode)
        try await playManager.load(podcastEpisode)
        await playManager.play()
      } catch {
        log.error(error)
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

      let episodeID = try await getEpisodeID(episode)
      try await queue.unshift(episodeID)
    }
  }

  func queueEpisodeAtBottom(_ episode: EpisodeType, swipeAction: Bool = false) {
    guard !isEpisodeAtBottomOfQueue(episode) else { return }

    Task { [weak self] in
      guard let self else { return }

      let episodeID = try await getEpisodeID(episode)
      try await queue.append(episodeID)
    }
  }

  func removeEpisodeFromQueue(_ episode: EpisodeType) {
    Task { [weak self] in
      guard let self else { return }

      do {
        let episodeID = try await getEpisodeID(episode)
        try await queue.dequeue(episodeID)
      } catch {
        log.error(error)
      }
    }
  }

  func cacheEpisode(_ episode: EpisodeType) {
    Task { [weak self] in
      guard let self else { return }

      do {
        let episodeID = try await getEpisodeID(episode)
        try await cacheManager.downloadToCache(for: episodeID)
      } catch {
        log.error(error)
      }
    }
  }

  func uncacheEpisode(_ episode: EpisodeType) {
    Task { [weak self] in
      guard let self else { return }

      do {
        let episodeID = try await getEpisodeID(episode)
        try await cacheManager.clearCache(for: episodeID)
      } catch {
        log.error(error)
      }
    }
  }

  func markEpisodeFinished(_ episode: EpisodeType) {
    guard !episode.finished else { return }

    Task { [weak self] in
      guard let self else { return }

      do {
        let episodeID = try await getEpisodeID(episode)
        try await repo.markFinished(episodeID)
      } catch {
        log.error(error)
      }
    }
  }

  func showPodcast(_ episode: EpisodeType) {
    Task { [weak self] in
      guard let self else { return }

      do {
        try await navigation.showPodcast(getOrCreatePodcastEpisode(episode).podcast)
      } catch {
        log.error(error)
      }
    }
  }

  func isEpisodePlaying(_ episode: EpisodeType) -> Bool {
    playState.isEpisodePlaying(episode)
  }

  func isEpisodeAtBottomOfQueue(_ episode: EpisodeType) -> Bool {
    episode.queueOrder == playState.maxQueuePosition
  }

  func canClearCache(_ episode: EpisodeType) -> Bool {
    CacheManager.canClearCache(episode)
  }

  func getOrCreatePodcastEpisode(_ episode: EpisodeType) async throws -> PodcastEpisode {
    try await DisplayedEpisode.getOrCreatePodcastEpisode(episode)
  }

  // MARK: - Helpers

  private func getEpisodeID(_ episode: EpisodeType) async throws -> Episode.ID {
    try await getOrCreatePodcastEpisode(episode).id
  }
}
