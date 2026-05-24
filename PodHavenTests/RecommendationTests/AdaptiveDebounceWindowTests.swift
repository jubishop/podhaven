// Copyright Justin Bishop, 2026

import Foundation
import Testing

@testable import PodHaven

@Suite("of AdaptiveDebounceWindow tests")
struct AdaptiveDebounceWindowTests {
  @Test("an empty window produces the minimum debounce floor")
  func emptyWindowReturnsMinimumDebounce() {
    let (duration, cappedFrom) = AdaptiveDebounceWindow.currentDebounce(for: [])

    #expect(duration == AdaptiveDebounceWindow.minimumDebounce)
    #expect(cappedFrom == nil)
  }

  @Test("a window with one slow entry produces max × safety multiplier")
  func slowEntryProducesSafetyMultipliedWindow() {
    let window = AdaptiveDebounceWindow.recording(.seconds(4), into: [])
    let (duration, cappedFrom) = AdaptiveDebounceWindow.currentDebounce(for: window)

    #expect(duration == .seconds(8))
    #expect(cappedFrom == nil)
  }

  @Test("a window with only sub-floor entries still floors at the minimum")
  func subFloorEntriesClampUpToFloor() {
    let window = AdaptiveDebounceWindow.recording(.milliseconds(100), into: [])
    let (duration, cappedFrom) = AdaptiveDebounceWindow.currentDebounce(for: window)

    #expect(duration == AdaptiveDebounceWindow.minimumDebounce)
    #expect(cappedFrom == nil)
  }

  @Test("a window whose max would exceed the cap clamps and reports the uncapped value")
  func aboveCapClampsAndSurfacesUncappedDuration() {
    // 70s * 2 = 140s, above the 120s cap.
    let window = AdaptiveDebounceWindow.recording(.seconds(70), into: [])
    let (duration, cappedFrom) = AdaptiveDebounceWindow.currentDebounce(for: window)

    #expect(duration == AdaptiveDebounceWindow.maximumDebounce)
    #expect(cappedFrom == .seconds(140))
  }

  @Test("capacity fast entries after a single slow entry age the slow entry out")
  func slowOutlierAgesOutAfterCapacityFastEntries() {
    var window = AdaptiveDebounceWindow.recording(.seconds(4), into: [])
    #expect(AdaptiveDebounceWindow.currentDebounce(for: window).duration == .seconds(8))

    for _ in 0..<AdaptiveDebounceWindow.capacity {
      window = AdaptiveDebounceWindow.recording(.milliseconds(50), into: window)
    }

    #expect(
      AdaptiveDebounceWindow.currentDebounce(for: window).duration
        == AdaptiveDebounceWindow.minimumDebounce
    )
  }

  @Test("the window holds at most capacity entries")
  func windowRespectsCapacity() {
    var window: [Duration] = []
    for _ in 0..<(AdaptiveDebounceWindow.capacity + 10) {
      window = AdaptiveDebounceWindow.recording(.milliseconds(100), into: window)
    }
    #expect(window.count == AdaptiveDebounceWindow.capacity)

    // A slow entry then `capacity` fast entries should drop the slow entry
    // out, returning the window to the floor.
    window = AdaptiveDebounceWindow.recording(.seconds(4), into: window)
    for _ in 0..<AdaptiveDebounceWindow.capacity {
      window = AdaptiveDebounceWindow.recording(.milliseconds(100), into: window)
    }
    #expect(
      AdaptiveDebounceWindow.currentDebounce(for: window).duration
        == AdaptiveDebounceWindow.minimumDebounce
    )
  }

  @Test("a [Duration] window round-trips through Codable")
  func windowRoundTripsThroughCodable() throws {
    var window: [Duration] = []
    window = AdaptiveDebounceWindow.recording(.seconds(2), into: window)
    window = AdaptiveDebounceWindow.recording(.seconds(3), into: window)
    window = AdaptiveDebounceWindow.recording(.milliseconds(500), into: window)

    let encoded = try JSONEncoder().encode(window)
    let decoded = try JSONDecoder().decode([Duration].self, from: encoded)

    #expect(decoded == window)
    #expect(
      AdaptiveDebounceWindow.currentDebounce(for: decoded).duration
        == AdaptiveDebounceWindow.currentDebounce(for: window).duration
    )
  }
}
