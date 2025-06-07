// Copyright Justin Bishop, 2025

import Foundation

@testable import PodHaven

class FakeAVPlayerItem: AVPlayableItem {
  let assetURL: MediaURL

  init(assetURL: MediaURL) {
    self.assetURL = assetURL
  }
}
