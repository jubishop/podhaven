// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

extension AVPlayerItem {
  var assetURL: URL {
    guard let urlAsset = asset as? AVURLAsset
    else { Assert.fatal("\(asset) is not an AVURLAsset") }

    return urlAsset.url
  }
}
