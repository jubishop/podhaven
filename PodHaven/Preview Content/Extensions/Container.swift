#if DEBUG && targetEnvironment(simulator)
// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation

extension Container: @retroactive AutoRegistering {
  public func autoRegister() {
    guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" else { return }
    appDB.context(.preview) { AppDB.inMemory() }.scope(.cached)
  }
}
#endif
