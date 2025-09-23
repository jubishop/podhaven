// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Logging

@MainActor protocol ManagingEpisodes: AnyObject {
  func playEpisode(_ episode: any EpisodeDisplayable)
  func pauseEpisode(_ episode: any EpisodeDisplayable)
  func queueEpisodeOnTop(_ episode: any EpisodeDisplayable)
  func queueEpisodeAtBottom(_ episode: any EpisodeDisplayable)
  func removeEpisodeFromQueue(_ episode: any EpisodeDisplayable)
  func cacheEpisode(_ episode: any EpisodeDisplayable)
  func uncacheEpisode(_ episode: any EpisodeDisplayable)
  func markEpisodeFinished(_ episode: any EpisodeDisplayable)
  func showPodcast(_ episode: any EpisodeDisplayable)

  func isEpisodePlaying(_ episode: any EpisodeDisplayable) -> Bool
  func isEpisodeAtBottomOfQueue(_ episode: any EpisodeDisplayable) -> Bool
  func canClearCache(_ episode: any EpisodeDisplayable) -> Bool

  func getOrCreatePodcastEpisode(_ episode: any EpisodeDisplayable) async throws -> PodcastEpisode
}

extension ManagingEpisodes {
  private var cacheManager: CacheManager { Container.shared.cacheManager() }
  private var repo: any Databasing { Container.shared.repo() }
  private var navigation: Navigation { Container.shared.navigation() }
  private var playManager: PlayManager { Container.shared.playManager() }
  private var playState: PlayState { Container.shared.playState() }
  private var queue: any Queueing { Container.shared.queue() }

  private var log: Logger { Log.as(LogSubsystem.ViewProtocols.podcast) }

  func playEpisode(_ episode: any EpisodeDisplayable) {
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

  func pauseEpisode(_ episode: any EpisodeDisplayable) {
    guard isEpisodePlaying(episode) else { return }

    Task { [weak self] in
      guard let self else { return }

      await playManager.pause()
    }
  }

  func queueEpisodeOnTop(_ episode: any EpisodeDisplayable) {
    Task { [weak self] in
      guard let self else { return }

      let episodeID = try await getEpisodeID(episode)
      try await queue.unshift(episodeID)
    }
  }

  func queueEpisodeAtBottom(_ episode: any EpisodeDisplayable) {
    Task { [weak self] in
      guard let self else { return }

      let episodeID = try await getEpisodeID(episode)
      try await queue.append(episodeID)
    }
  }

  func removeEpisodeFromQueue(_ episode: any EpisodeDisplayable) {
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

  func cacheEpisode(_ episode: any EpisodeDisplayable) {
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

  func uncacheEpisode(_ episode: any EpisodeDisplayable) {
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

  func markEpisodeFinished(_ episode: any EpisodeDisplayable) {
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

  func showPodcast(_ episode: any EpisodeDisplayable) {
    Task { [weak self] in
      guard let self else { return }

      do {
        try await navigation.showPodcast(getOrCreatePodcastEpisode(episode).podcast)
      } catch {
        log.error(error)
      }
    }
  }

  func isEpisodePlaying(_ episode: any EpisodeDisplayable) -> Bool {
    playState.isEpisodePlaying(episode)
  }

  func isEpisodeAtBottomOfQueue(_ episode: any EpisodeDisplayable) -> Bool {
    episode.queueOrder == playState.maxQueuePosition
  }

  func canClearCache(_ episode: any EpisodeDisplayable) -> Bool {
    CacheManager.canClearCache(episode)
  }

  func getOrCreatePodcastEpisode(_ episode: any EpisodeDisplayable) async throws -> PodcastEpisode {
    try await DisplayedEpisode.getOrCreatePodcastEpisode(episode)
  }

  // MARK: - Helpers

  private func getEpisodeID(_ episode: any EpisodeDisplayable) async throws -> Episode.ID {
    try await getOrCreatePodcastEpisode(episode).id
  }
}
