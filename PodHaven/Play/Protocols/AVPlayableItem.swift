// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

@MainActor protocol AVPlayableItem: AnyObject {
  var assetURL: MediaURL { get }
}
