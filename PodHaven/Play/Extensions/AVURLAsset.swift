// Copyright Justin Bishop, 2025

import AVFoundation
import AssociatedObject
import Foundation

extension AVURLAsset {
  @AssociatedObject(.retain(.atomic))
  var episodeID: Episode.ID?
}
