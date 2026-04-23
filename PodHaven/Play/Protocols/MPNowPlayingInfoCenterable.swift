// Copyright Justin Bishop, 2025

import Foundation
import MediaPlayer

protocol MPNowPlayingInfoCenterable {
  var nowPlayingInfo: [String: Any]? { get set }
  var playbackState: MPNowPlayingPlaybackState { get set }
}
