// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Logging

@MainActor protocol PodcastQueueableModel: AnyObject, EpisodeQueueable {
  associatedtype EpisodeType

  func getPodcastEpisode(_ episode: EpisodeType) async throws -> PodcastEpisode
  func getEpisodeID(_ episode: EpisodeType) async throws -> Episode.ID
}

extension PodcastQueueableModel {
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
}

extension PodcastQueueableModel where EpisodeType == PodcastEpisode {
  func getPodcastEpisode(_ episode: PodcastEpisode) async throws -> PodcastEpisode { episode }
  func getEpisodeID(_ episode: PodcastEpisode) async throws -> Episode.ID { episode.id }
}

extension PodcastQueueableModel where EpisodeType == Episode {
  func getEpisodeID(_ episode: Episode) async throws -> Episode.ID { episode.id }
}
