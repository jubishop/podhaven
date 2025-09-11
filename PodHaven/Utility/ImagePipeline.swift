// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Nuke

extension Container {
  var imagePipeline: Factory<ImagePipeline> {
    Factory(self) { ImagePipeline.shared }.scope(.cached)
  }
}
