// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import GRDB
import Logging

@Observable @MainActor class EpisodeDetailViewModel: EpisodeDetailViewableModel {
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory
  @ObservationIgnored @DynamicInjected(\.playManager) private var playManager
  @ObservationIgnored @DynamicInjected(\.playState) private var playState
  @ObservationIgnored @DynamicInjected(\.queue) private var queue
  @ObservationIgnored @DynamicInjected(\.repo) private var repo

  private static let log = Log.as(LogSubsystem.EpisodesView.detail)

  // MARK: - State Management

  private let episode: any EpisodeDisplayable
  private var podcastEpisode: PodcastEpisode?
  internal var maxQueuePosition: Int? = nil

  // MARK: - Initialization

  init(episode: any EpisodeDisplayable) {
    self.episode = episode
  }

  func execute() async {
    await withTaskGroup { group in
      // Observe max queue position
      group.addTask { @MainActor @Sendable in
        do {
          for try await maxPosition in self.observatory.maxQueuePosition() {
            try Task.checkCancellation()
            self.maxQueuePosition = maxPosition
          }
        } catch {
          Self.log.error(error)
          guard ErrorKit.isRemarkable(error) else { return }
          self.alert(ErrorKit.message(for: error))
        }
      }

      // Observe this episode record updates
      group.addTask { @MainActor @Sendable in
        do {
          for try await podcastEpisode in self.observatory.podcastEpisode(self.episode.mediaURL) {
            try Task.checkCancellation()
            Self.log.debug(
              "Updating observed podcast: \(String(describing: podcastEpisode?.toString))"
            )
            self.podcastEpisode = podcastEpisode
          }
        } catch {
          Self.log.error(error)
          guard ErrorKit.isRemarkable(error) else { return }
          self.alert(ErrorKit.message(for: error))
        }
      }
    }
  }

  // MARK: - EpisodeDetailViewableModel

  func getPodcastEpisode() -> PodcastEpisode? { podcastEpisode }
  func getOrCreatePodcastEpisode() async throws -> PodcastEpisode {
    if let podcastEpisode = self.podcastEpisode { return podcastEpisode }

    let podcastEpisode: PodcastEpisode
    if let unsavedPodcastEpisode = episode as? UnsavedPodcastEpisode {
      podcastEpisode = try await repo.upsertPodcastEpisode(unsavedPodcastEpisode)
    } else if let existingPodcastEpisode = episode as? PodcastEpisode {
      podcastEpisode = existingPodcastEpisode
    } else {
      Assert.fatal("Unsupported episode type: \(type(of: episode))")
    }

    self.podcastEpisode = podcastEpisode
    return podcastEpisode
  }

  var episodeTitle: String { episode.title }
  var episodePubDate: Date { episode.pubDate }
  var episodeDuration: CMTime { episode.duration }
  var episodeCached: Bool { episode.cached }
  var episodeImage: URL { episode.image }
  var episodeDescription: String? { episode.description }
  var podcastTitle: String { episode.podcastTitle }
}
