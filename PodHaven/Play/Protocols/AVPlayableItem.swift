// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

@MainActor protocol AVPlayableItem: AnyObject, CustomStringConvertible {
  var episodeID: Episode.ID? { get }
}
