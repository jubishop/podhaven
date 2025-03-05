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
        savedEpisodes.append(podcastEpisode)
        toReturn.append(podcastEpisode)
      }
    }

    return toReturn
  }

  func fetchOrCreate(_ unsavedPodcastEpisodes: [UnsavedPodcastEpisode]) async throws
    -> [PodcastEpisode]
  {
    var toReturn: [PodcastEpisode] = []
    toReturn.reserveCapacity(unsavedPodcastEpisodes.count)
    var toFetchOrCreate: [UnsavedPodcastEpisode] = []
    toFetchOrCreate.reserveCapacity(unsavedPodcastEpisodes.count)

    for unsavedPodcastEpisode in unsavedPodcastEpisodes {
      let mediaURL = unsavedPodcastEpisode.unsavedEpisode.media
      if let savedEpisode = savedEpisodes[id: mediaURL] {
        toReturn.append(savedEpisode)
      } else if !attemptedEpisodes.contains(mediaURL) {
        toFetchOrCreate.append(unsavedPodcastEpisode)
      }
      attemptedEpisodes.insert(mediaURL)
    }

    if !toFetchOrCreate.isEmpty {
      let fetchedPodcastEpisodes = try await repo.episodes(toFetch)

      for podcastEpisode in fetchedPodcastEpisodes {
        savedEpisodes.append(podcastEpisode)
        toReturn.append(podcastEpisode)
      }
    }

    return toReturn
  }
}
