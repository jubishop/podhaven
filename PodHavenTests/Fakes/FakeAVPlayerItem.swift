// Copyright Justin Bishop, 2025

import Foundation

@testable import PodHaven

class FakeAVPlayerItem: AVPlayableItem {
  let assetURL: URL

  init(assetURL: URL) {
    self.assetURL = assetURL
  }
}
