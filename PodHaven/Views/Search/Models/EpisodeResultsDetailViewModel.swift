// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import GRDB
import Logging

@Observable @MainActor class EpisodeResultsDetailViewModel: EpisodeDetailViewableModel {
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory
  @ObservationIgnored @DynamicInjected(\.playManager) private var playManager
  @ObservationIgnored @DynamicInjected(\.playState) private var playState
  @ObservationIgnored @DynamicInjected(\.queue) private var queue
  @ObservationIgnored @DynamicInjected(\.repo) private var repo

  private static let log = Log.as(LogSubsystem.EpisodesView.detail)

  // MARK: - State Management

  private let searchedText: String
  private let unsavedPodcastEpisode: UnsavedPodcastEpisode

  internal var maxQueuePosition: Int? = nil
  private var podcastEpisode: PodcastEpisode?

  // MARK: - Initialization

  init(searchedPodcastEpisode: SearchedPodcastEpisode) {
    self.searchedText = searchedPodcastEpisode.searchedText
    self.unsavedPodcastEpisode = searchedPodcastEpisode.unsavedPodcastEpisode
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
          for try await podcastEpisode in self.observatory.podcastEpisode(
            self.unsavedPodcastEpisode.unsavedEpisode.media
          ) {
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

    let podcastEpisode = try await repo.upsertPodcastEpisode(unsavedPodcastEpisode)
    self.podcastEpisode = podcastEpisode
    return podcastEpisode
  }

  var episodeTitle: String { unsavedPodcastEpisode.unsavedEpisode.title }
  var episodePubDate: Date { unsavedPodcastEpisode.unsavedEpisode.pubDate }
  var episodeDuration: CMTime { unsavedPodcastEpisode.unsavedEpisode.duration }
  var episodeCachedFilename: String? { unsavedPodcastEpisode.unsavedEpisode.cachedFilename }
  var episodeImage: URL { unsavedPodcastEpisode.image }
  var episodeDescription: String? { unsavedPodcastEpisode.unsavedEpisode.description }
  var podcastTitle: String { unsavedPodcastEpisode.unsavedPodcast.title }

}
