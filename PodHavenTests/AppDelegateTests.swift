// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Testing
import UIKit

@testable import PodHaven

@Suite("of AppDelegate background session handling", .container)
@MainActor struct AppDelegateTests {
  @Test("background launch recreates the cache session")
  func backgroundLaunchRecreatesCacheSession() {
    let resolutionCount = ThreadSafe<Int>(0)
    let session = FakeDataFetchable()
    Container.shared.cacheManagerSession
      .context(.test) {
        resolutionCount { $0 += 1 }
        return session
      }
      .scope(.cached)
    Container.shared.cacheManagerSession.reset(.scope)

    AppDelegate()
      .application(
        UIApplication.shared,
        handleEventsForBackgroundURLSession: "test.cache.bg",
        completionHandler: {}
      )

    #expect(resolutionCount() == 1)
  }
}
