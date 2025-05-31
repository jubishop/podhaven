// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of PlayManager tests", .container)
actor PlayManagerTests {
  @Test("example")
  func example() async throws {
    let playManager = Container.shared.playManager()
    await playManager.start()
    //    let continuation = try await Notifier.get(AVAudioSession.interruptionNotification)
    //continuation.yield(Notification(name: .init("Test")))

    #expect("Test" == "Test")
  }
}
