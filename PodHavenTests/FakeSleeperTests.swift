// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("FakeSleeper Tests", .container)
struct FakeSleeperTests {
  private var sleeper: FakeSleeper {
    Container.shared.sleeper() as! FakeSleeper
  }

  @Test("Basic sleep and advance time")
  func basicSleepAndAdvance() async throws {
    var completed = false

    let task = Task {
      try await sleeper.sleep(for: .seconds(5))
      completed = true
    }

    try await sleeper.waitForRegistrations(count: 1)

    await sleeper.advanceTime(by: .seconds(1))
    #expect(!completed)

    await sleeper.advanceTime(by: .seconds(4))  // Total 5 seconds
    try await task.value
    #expect(completed)
  }

  @Test("Multiple sleep requests with different durations")
  func multipleSleepRequests() async throws {
    let tracker = ActorArray<Int>()

    let task1 = Task {
      try await sleeper.sleep(for: .seconds(3))
      await tracker.append(1)
    }

    let task2 = Task {
      try await sleeper.sleep(for: .seconds(1))
      await tracker.append(2)
    }

    let task3 = Task {
      try await sleeper.sleep(for: .seconds(2))
      await tracker.append(3)
    }

    try await sleeper.waitForRegistrations(count: 3)

    // Advance time by 1 second - only task2 should complete
    await sleeper.advanceTime(by: .seconds(1))
    try await task2.value
    #expect(await tracker.getItems() == [2])

    // Advance time by 1 more second - task3 should complete
    await sleeper.advanceTime(by: .seconds(1))
    try await task3.value
    #expect(await tracker.getItems() == [2, 3])

    // Advance time by 1 more second - task1 should complete
    await sleeper.advanceTime(by: .seconds(1))
    try await task1.value
    #expect(await tracker.getItems() == [2, 3, 1])
  }

  @Test("Partial time advancement")
  func partialTimeAdvancement() async throws {
    var completed = false

    let task = Task {
      try await sleeper.sleep(for: .seconds(10))
      completed = true
    }

    try await sleeper.waitForRegistrations(count: 1)

    // Advance time partially
    await sleeper.advanceTime(by: .seconds(5))
    #expect(!completed)

    // Advance remaining time
    await sleeper.advanceTime(by: .seconds(5))
    try await task.value
    #expect(completed)
  }

  @Test("Sleep requests started at different times")
  func sleepRequestsAtDifferentTimes() async throws {
    let tracker = ActorArray<Int>()

    // Start first sleep (wakeTime = 0 + 3 = 3)
    let task1 = Task {
      try await sleeper.sleep(for: .seconds(3))
      await tracker.append(1)
    }

    try await sleeper.waitForRegistrations(count: 1)

    // Advance time by 1 second
    await sleeper.advanceTime(by: .seconds(1))

    // Start second sleep (wakeTime = 1 + 2 = 3)
    let task2 = Task {
      try await sleeper.sleep(for: .seconds(2))
      await tracker.append(2)
    }

    try await sleeper.waitForRegistrations(count: 2)

    // Advance time by 2 more seconds (total 3 seconds from start)
    await sleeper.advanceTime(by: .seconds(2))

    try await task1.value
    try await task2.value

    // Both should complete at the same time
    #expect(await tracker.count() == 2)
    #expect(await tracker.contains(1))
    #expect(await tracker.contains(2))
  }
}
