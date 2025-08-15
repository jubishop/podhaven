// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation

extension Container {
  public func previewAutoRegister() {
    appDB.context(.preview) { AppDB.inMemory() }.scope(.cached)
  }
}
