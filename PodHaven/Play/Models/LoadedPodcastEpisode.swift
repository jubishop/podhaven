// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

struct LoadedPodcastEpisode: Stringable {
  let item: AVPlayerItem
  let podcastEpisode: PodcastEpisode
  let duration: CMTime

  // MARK: - Stringable

  var toString: String { podcastEpisode.toString }
}
