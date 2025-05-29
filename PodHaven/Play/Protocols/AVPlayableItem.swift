// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

@MainActor
protocol AVPlayableItem {
  var asset: AVAsset { get }
  var assetURL: URL { get }
}

extension AVPlayableItem {
  var assetURL: URL {
    guard let urlAsset = asset as? AVURLAsset
    else { fatalError("\(asset) is not an AVURLAsset") }

    return urlAsset.url
  }
}

extension AVPlayerItem: AVPlayableItem {}
