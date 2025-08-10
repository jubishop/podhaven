// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation

extension Container: @retroactive AutoRegistering {
  public func autoRegister() {
    appDB.context(.preview) { AppDB.inMemory() }.scope(.cached)
  }
}
