// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("Background task expiration context", .container)
struct BackgroundTaskExpirationContextTests {
  @Test("expiration context belongs to the grant and precedes cancellation")
  func expiration() async throws {
    let os = Container.shared.bgTaskScheduler() as! FakeBGTaskScheduler
    let scheduler = BackgroundTaskScheduler(
      identifier: "context",
      cadence: .minutes(1),
      taskType: .appRefresh
    )
    let contexts = ThreadSafe<[BackgroundTaskScheduler.ExecutionContext]>([])
    let observed = ThreadSafe<[Bool]>([])
    let gate = AsyncLatch<Void>()
    scheduler.register { complete, context in
      contexts { $0.append(context) }
      do { try await gate.wait() } catch {}
      observed { $0.append(context.isExpired) }
      complete(!Task.isCancelled)
    }
    let first = try #require(os.launchTask(withIdentifier: "context"))
    try await Wait.until {
      contexts().count == 1
    } _: {
      "First grant did not start"
    }
    first.expire()
    try await Wait.until {
      first.completionCount == 1
    } _: {
      "Expired grant did not complete"
    }
    #expect(contexts()[0].isExpired)
    try await Wait.until {
      observed().count == 1
    } _: {
      "Cancellation did not reach the grant"
    }
    #expect(observed() == [true])
    let second = try #require(os.launchTask(withIdentifier: "context"))
    try await Wait.until {
      contexts().count == 2
    } _: {
      "Second grant did not start"
    }
    #expect(!contexts()[1].isExpired)
    gate.open()
    try await Wait.until {
      second.completionCount == 1
    } _: {
      "Second grant did not complete"
    }
    second.expire()
    #expect(!contexts()[1].isExpired)
    #expect(first.completionResults == [false])
    #expect(second.completionResults == [true])
  }

  @Test("app cancellation does not falsely report iOS expiration")
  func cancellation() async throws {
    let os = Container.shared.bgTaskScheduler() as! FakeBGTaskScheduler
    let scheduler = BackgroundTaskScheduler(
      identifier: "cancel",
      cadence: .minutes(1),
      taskType: .appRefresh,
      expirationBehavior: .awaitCancellation
    )
    let context = ThreadSafe<BackgroundTaskScheduler.ExecutionContext?>(nil)
    let gate = AsyncLatch<Void>()
    scheduler.register { complete, execution in
      context(execution)
      do { try await gate.wait() } catch {}
      complete(!Task.isCancelled)
    }
    let task = try #require(os.launchTask(withIdentifier: "cancel"))
    try await Wait.until {
      context() != nil
    } _: {
      "Grant did not start"
    }
    scheduler.cancelRunningTasks()
    try await Wait.until {
      task.completionCount == 1
    } _: {
      "Cancelled grant did not complete"
    }
    #expect(context()?.isExpired == false)
    #expect(task.completionResults == [false])
  }
}
