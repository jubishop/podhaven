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

  internal var maxQueuePosition: Int? = nil
  private var podcastEpisode: PodcastEpisode

  // MARK: - Initialization

  init(podcastEpisode: PodcastEpisode) {
    self.podcastEpisode = podcastEpisode
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
          for try await podcastEpisode in self.observatory.podcastEpisode(self.podcastEpisode.id) {
            try Task.checkCancellation()

            guard let podcastEpisode = podcastEpisode
            else {
              throw ObservatoryError.recordNotFound(
                type: PodcastEpisode.self,
                id: self.podcastEpisode.episode.id.rawValue
              )
            }

            Self.log.debug("Updating observed podcast: \(podcastEpisode.toString)")
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
  func getOrCreatePodcastEpisode() async throws -> PodcastEpisode { podcastEpisode }

  var episodeTitle: String { podcastEpisode.episode.title }
  var episodePubDate: Date { podcastEpisode.episode.pubDate }
  var episodeDuration: CMTime { podcastEpisode.episode.duration }
  var episodeCached: Bool { podcastEpisode.episode.cached }
  var episodeImage: URL { podcastEpisode.image }
  var episodeDescription: String? { podcastEpisode.episode.description }
  var podcastTitle: String { podcastEpisode.podcast.title }
}
