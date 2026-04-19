// Copyright Justin Bishop, 2025

import Foundation
import MediaPlayer

@testable import PodHaven

class FakeMPNowPlayingInfoCenter: MPNowPlayingInfoCenterable {
  var nowPlayingInfo: [String: Any]?
  var playbackState: MPNowPlayingPlaybackState = .unknown
}
