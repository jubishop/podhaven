// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

@MainActor protocol AVPlayableItem {
  var assetURL: URL { get }
}
