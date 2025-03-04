// Copyright Justin Bishop, 2025

import Factory
import Foundation
import IdentifiedCollections

class EpisodeCache {
  @ObservationIgnored @LazyInjected(\.repo) private var repo

  // MARK: - State Management

  private var attemptedEpisodes: Set<MediaURL> = []
  private var savedEpisodes: PodcastEpisodeArray = IdentifiedArray(id: \.episode.media)

  // MARK: - Public Functions

  func fetch(_ mediaURLs: [MediaURL]) async throws -> [PodcastEpisode] {
    var toReturn: [PodcastEpisode] = []
    toReturn.reserveCapacity(mediaURLs.count)
    var toFetch: [MediaURL] = []
    toFetch.reserveCapacity(mediaURLs.count)

    for mediaURL in mediaURLs {
      if let savedEpisode = savedEpisodes[id: mediaURL] {
        toReturn.append(savedEpisode)
      } else if !attemptedEpisodes.contains(mediaURL) {
        toFetch.append(mediaURL)
      }
      attemptedEpisodes.insert(mediaURL)
    }

    if !toFetch.isEmpty {
      let fetchedPodcastEpisodes = try await repo.episodes(toFetch)

      for podcastEpisode in fetchedPodcastEpisodes {
        savedEpisodes[id: podcastEpisode.episode.media] = podcastEpisode
        toReturn.append(podcastEpisode)
      }
    }

    return toReturn
  }

  //  func fetchOrCreate(_ unsavedEpisodes: [UnsavedEpisode]) async throws -> [Episode] {
  //
  //  }
}
