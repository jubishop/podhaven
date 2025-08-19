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

  let searchedText: String

  private var podcastEpisode: PodcastEpisode?
  let unsavedPodcastEpisode: UnsavedPodcastEpisode
  internal var maxQueuePosition: Int? = nil

  // MARK: - Initialization

  init(searchedPodcastEpisode: SearchedPodcastEpisode) {
    self.searchedText = searchedPodcastEpisode.searchedText
    self.unsavedPodcastEpisode = searchedPodcastEpisode.unsavedPodcastEpisode
  }

  func execute() async {
    // Observe max queue position
    Task { [weak self] in
      guard let self else { return }
      do {
        for try await maxPosition in observatory.maxQueuePosition() {
          self.maxQueuePosition = maxPosition
        }
      } catch {
        Self.log.error(error)
        alert(ErrorKit.message(for: error))
      }
    }

    // Observe this episode record updates
    Task { [weak self] in
      guard let self else { return }
      do {
        for try await podcastEpisode in observatory.podcastEpisode(
          unsavedPodcastEpisode.unsavedEpisode.media
        ) {
          if self.podcastEpisode == podcastEpisode { continue }
          self.podcastEpisode = podcastEpisode
        }
      } catch {
        alert("Couldn't observe podcast episode: \(unsavedPodcastEpisode.toString)")
      }
    }
  }

  // MARK: - EpisodeDetailViewableModel

  func getPodcastEpisode() -> PodcastEpisode? {
    podcastEpisode
  }

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
