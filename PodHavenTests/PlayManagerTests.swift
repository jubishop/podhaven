// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of PlayManager tests", .container)
struct PlayManagerTests {
  @DynamicInjected(\.commandCenter) private var injectedCommandCenter
  @DynamicInjected(\.avQueuePlayer) private var injectedAVQueuePlayer

  var commandCenter: FakeCommandCenter { injectedCommandCenter as! FakeCommandCenter }
  var avQueuePlayer: FakeAVQueuePlayer { injectedAVQueuePlayer as! FakeAVQueuePlayer }

  @Test("example")
  func example() async throws {
    let playManager = Container.shared.playManager()
    await playManager.start()
    // let continuation = try await Notifier.get(AVAudioSession.interruptionNotification)
    // continuation.yield(Notification(name: .init("Test")))

    //commandCenter.continuation.yield(.play)
    //commandCenter.continuation.yield(.pause)
  }

  @MainActor @Test("queue player interaction")
  func queuePlayerInteraction() async throws {
    // Setup test items
    let item1 = FakeAVPlayerItem(assetURL: URL(filePath: "episode1.mp3")!)
    let item2 = FakeAVPlayerItem(assetURL: URL(filePath: "episode2.mp3")!)

    // Add items to queue
    avQueuePlayer.insert(item1, after: nil)
    avQueuePlayer.insert(item2, after: item1)

    // Verify queue state
    #expect(avQueuePlayer.items().count == 2)
    #expect(avQueuePlayer.isPlaying == false)

    // Simulate play
    avQueuePlayer.play()
    #expect(avQueuePlayer.isPlaying == true)

    // Simulate time advancement and trigger time observers
    avQueuePlayer.simulateTimeAdvancement(by: 10.0)
    avQueuePlayer.triggerTimeObservers()

    // Test seeking
    let seekTime = CMTime.inSeconds(30)
    avQueuePlayer.seek(to: seekTime) { success in
      #expect(success == true)
    }
    #expect(avQueuePlayer.currentTime() == seekTime)

    // Test pause
    avQueuePlayer.pause()
    #expect(avQueuePlayer.isPlaying == false)
  }
}
