// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation

@testable import PodHaven

extension Container: @retroactive AutoRegistering {
  public func autoRegister() {
    appDB.context(.test) { AppDB.inMemory() }.scope(.cached)
    searchServiceSession.context(.test) { DataFetchableMock() }.scope(.cached)
    feedManagerSession.context(.test) { DataFetchableMock() }.scope(.cached)
  }
}
