// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

struct LoadedPodcastEpisode: Identifiable, Stringable {
  var id: Episode.ID { podcastEpisode.id }

  let podcastEpisode: PodcastEpisode
  let duration: CMTime

  var assetURL: MediaURL { podcastEpisode.episode.media }

  // MARK: - Stringable

  var toString: String { "[\(duration)]: \(podcastEpisode.toString)" }
}
