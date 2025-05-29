// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

extension AVPlayerItem: AVPlayableItem {
  var assetURL: URL {
    guard let urlAsset = asset as? AVURLAsset
    else { fatalError("\(asset) is not an AVURLAsset") }

    return urlAsset.url
  }
}
