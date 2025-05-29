// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

struct EpisodeInfo: Stringable {
  let podcastEpisode: PodcastEpisode
  let duration: CMTime

  // MARK: - Stringable

  var toString: String { podcastEpisode.toString }
}

struct LoadedPodcastEpisode: Stringable {
  let item: any AVPlayableItem
  let podcastEpisode: PodcastEpisode
  let duration: CMTime

  var episodeInfo: EpisodeInfo {
    EpisodeInfo(podcastEpisode: podcastEpisode, duration: duration)
  }

  // MARK: - Stringable

  var toString: String { podcastEpisode.toString }

  // MARK: - Hashable

  func hash(into hasher: inout Hasher) {
    hasher.combine(podcastEpisode)
  }

  // MARK: - Equatable

  static func == (lhs: LoadedPodcastEpisode, rhs: LoadedPodcastEpisode) -> Bool {
    lhs.podcastEpisode == rhs.podcastEpisode
  }
}
