// Copyright Justin Bishop, 2026

import Foundation
import Testing

@testable import PodHaven

@Suite("of AdaptiveDebounceWindow tests")
struct AdaptiveDebounceWindowTests {
  @Test("an empty window produces the minimum debounce floor")
  func emptyWindowReturnsMinimumDebounce() {
    let window = AdaptiveDebounceWindow()
    let (duration, cappedFrom) = window.currentDebounce()

    #expect(duration == AdaptiveDebounceWindow.minimumDebounce)
    #expect(cappedFrom == nil)
  }

  @Test("a window with one slow entry produces max × safety multiplier")
  func slowEntryProducesSafetyMultipliedWindow() {
    let window = AdaptiveDebounceWindow().recording(.seconds(4))
    let (duration, cappedFrom) = window.currentDebounce()

    #expect(duration == .seconds(8))
    #expect(cappedFrom == nil)
  }

  @Test("a window with only sub-floor entries still floors at the minimum")
  func subFloorEntriesClampUpToFloor() {
    let window = AdaptiveDebounceWindow().recording(.milliseconds(100))
    let (duration, cappedFrom) = window.currentDebounce()

    #expect(duration == AdaptiveDebounceWindow.minimumDebounce)
    #expect(cappedFrom == nil)
  }

  @Test("a window whose max would exceed the cap clamps and reports the uncapped value")
  func aboveCapClampsAndSurfacesUncappedDuration() {
    // 70s * 2 = 140s, above the 120s cap.
    let window = AdaptiveDebounceWindow().recording(.seconds(70))
    let (duration, cappedFrom) = window.currentDebounce()

    #expect(duration == AdaptiveDebounceWindow.maximumDebounce)
    #expect(cappedFrom == .seconds(140))
  }

  @Test("five fast entries after a single slow entry age the slow entry out")
  func slowOutlierAgesOutAfterCapacityFastEntries() {
    var window = AdaptiveDebounceWindow().recording(.seconds(4))
    // After the slow entry, debounce should reflect it.
    #expect(window.currentDebounce().duration == .seconds(8))

    // Record `capacity` sub-floor entries. After the last one, the slow
    // outlier should have been trimmed out and the debounce should be back
    // at the floor.
    for _ in 0..<AdaptiveDebounceWindow.capacity {
      window = window.recording(.milliseconds(50))
    }

    #expect(window.currentDebounce().duration == AdaptiveDebounceWindow.minimumDebounce)
  }

  @Test("the window holds at most capacity entries")
  func windowRespectsCapacity() {
    var window = AdaptiveDebounceWindow()
    for _ in 0..<(AdaptiveDebounceWindow.capacity + 10) {
      window = window.recording(.milliseconds(100))
    }
    // No direct observable for count, but the rolling-max behavior is the
    // contract: a recently-recorded slow entry should not stay forever.
    window = window.recording(.seconds(4))
    for _ in 0..<AdaptiveDebounceWindow.capacity {
      window = window.recording(.milliseconds(100))
    }
    #expect(window.currentDebounce().duration == AdaptiveDebounceWindow.minimumDebounce)
  }

  @Test("the window round-trips through Codable")
  func windowRoundTripsThroughCodable() throws {
    var window = AdaptiveDebounceWindow()
    window = window.recording(.seconds(2))
    window = window.recording(.seconds(3))
    window = window.recording(.milliseconds(500))

    let encoded = try JSONEncoder().encode(window)
    let decoded = try JSONDecoder().decode(AdaptiveDebounceWindow.self, from: encoded)

    #expect(decoded == window)
    #expect(decoded.currentDebounce().duration == window.currentDebounce().duration)
  }
}
