// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation
import AssociatedObject

extension AVURLAsset {
  @AssociatedObject(.retain(.atomic))
  var episodeID: Episode.ID?
}
