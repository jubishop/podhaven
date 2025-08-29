// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Logging

@MainActor protocol ManagingEpisodesModel: AnyObject, ManagingEpisodes {
  associatedtype EpisodeType

  func getPodcastEpisode(_ episode: EpisodeType) async throws -> PodcastEpisode
  func getEpisodeID(_ episode: EpisodeType) async throws -> Episode.ID
}

extension ManagingEpisodesModel {
  private var cacheManager: CacheManager { Container.shared.cacheManager() }
  private var playManager: PlayManager { Container.shared.playManager() }
  private var queue: any Queueing { Container.shared.queue() }

  private var log: Logger { Log.as(LogSubsystem.ViewProtocols.podcast) }

  func playEpisode(_ episode: EpisodeType) {
    Task { [weak self] in
      guard let self else { return }
      do {
        let podcastEpisode = try await getPodcastEpisode(episode)
        try await playManager.load(podcastEpisode)
        await playManager.play()
      } catch {
        log.error(error)
      }
    }
  }

  func queueEpisodeOnTop(_ episode: EpisodeType) {
    Task { [weak self] in
      guard let self else { return }
      let episodeID = try await getEpisodeID(episode)
      try await queue.unshift(episodeID)
    }
  }

  func queueEpisodeAtBottom(_ episode: EpisodeType) {
    Task { [weak self] in
      guard let self else { return }
      let episodeID = try await getEpisodeID(episode)
      try await queue.append(episodeID)
    }
  }
  
  func cacheEpisode(_ episode: EpisodeType) {
    Task { [weak self] in
      guard let self else { return }
      do {
        let podcastEpisode = try await getPodcastEpisode(episode)
        try await cacheManager.downloadAndCache(podcastEpisode)
      } catch {
        log.error(error)
      }
    }
  }
}

extension ManagingEpisodesModel where EpisodeType == PodcastEpisode {
  func getPodcastEpisode(_ episode: PodcastEpisode) async throws -> PodcastEpisode { episode }
}

extension ManagingEpisodesModel {
  func getEpisodeID(_ episode: EpisodeType) async throws -> Episode.ID {
    try await getPodcastEpisode(episode).id
  }
}
