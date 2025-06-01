// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation

@testable import PodHaven

extension Container: @retroactive AutoRegistering {
  public func autoRegister() {
    appDB.context(.test) { AppDB.inMemory() }.scope(.cached)
    searchServiceSession.context(.test) { FakeDataFetchable() }.scope(.cached)
    feedManagerSession.context(.test) { FakeDataFetchable() }.scope(.cached)
    notifications.context(.test) {
      { name in AsyncStream { continuation in Notifier.set(name, continuation) } }
    }
    commandCenter.context(.test) { FakeCommandCenter() }.scope(.cached)
    avQueuePlayer.context(.test) { @MainActor in FakeAVQueuePlayer() }.scope(.cached)
  }
}
