// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Logging

@MainActor protocol ManagingEpisodesModel: AnyObject, ManagingEpisodes {}

extension ManagingEpisodesModel {
  private var cacheManager: CacheManager { Container.shared.cacheManager() }
  private var playManager: PlayManager { Container.shared.playManager() }
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

  func cacheEpisode(_ episode: any EpisodeDisplayable) {
    Task { [weak self] in
      guard let self else { return }
      do {
        let podcastEpisode = try await getOrCreatePodcastEpisode(episode)
        try await cacheManager.downloadAndCache(podcastEpisode)
      } catch {
        log.error(error)
      }
    }
  }

  // MARK: - Helpers

  private func getOrCreatePodcastEpisode(_ episode: any EpisodeDisplayable) async throws
    -> PodcastEpisode
  {
    try await DisplayableEpisode.getOrCreatePodcastEpisode(episode)
  }

  private func getEpisodeID(_ episode: any EpisodeDisplayable) async throws -> Episode.ID {
    try await getOrCreatePodcastEpisode(episode).id
  }
}
