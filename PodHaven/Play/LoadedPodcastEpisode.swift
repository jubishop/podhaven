// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

struct LoadedPodcastEpisode {
  let item: AVPlayerItem
  let podcastEpisode: PodcastEpisode
  let duration: CMTime
}
