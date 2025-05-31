// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of PlayManager tests", .container)
actor PlayManagerTests {
  @DynamicInjected(\.commandCenter) private var injectedCommandCenter

  var commandCenter: FakeCommandCenter { injectedCommandCenter as! FakeCommandCenter }

  @Test("example")
  func example() async throws {
    let playManager = Container.shared.playManager()
    await playManager.start()
    // let continuation = try await Notifier.get(AVAudioSession.interruptionNotification)
    // continuation.yield(Notification(name: .init("Test")))

    // commandCenter.continuation.yield(.play)
    #expect("Test" == "Test")
  }
}
