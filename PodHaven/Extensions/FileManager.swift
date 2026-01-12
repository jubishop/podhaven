// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation

extension Container {
  var fileManager: Factory<any FileManaging> {
    Factory(self) { FileManager.default }.scope(.cached)
  }
}

extension FileManager: FileManaging {}
