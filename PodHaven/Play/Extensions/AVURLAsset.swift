// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation
import SwiftAssociatedObject

extension AVURLAsset {
  private var episodeIDAssociated: AssociatedObject<Episode.ID?> {
    AssociatedObject(self, key: "episodeID", initValue: nil)
  }

  var episodeID: Episode.ID? {
    get { episodeIDAssociated() }
    set { episodeIDAssociated(newValue) }
  }
}
