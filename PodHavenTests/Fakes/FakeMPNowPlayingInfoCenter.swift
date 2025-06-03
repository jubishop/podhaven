// Copyright Justin Bishop, 2025

import Foundation

@testable import PodHaven

class FakeMPNowPlayingInfoCenter: MPNowPlayingInfoCenterable {
  var nowPlayingInfo: [String: Any]?
}
