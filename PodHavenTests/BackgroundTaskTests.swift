// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Testing
import UIKit

@testable import PodHaven

@Suite("of BackgroundTask tests", .container)
@MainActor struct BackgroundTaskTests {
  @DynamicInjected(\.uiApplication) private var uiApplication

  var fakeApplication: FakeApplication { uiApplication as! FakeApplication }

  // MARK: - Start Tests

  @Test("that starting a background task calls beginBackgroundTask")
  func testStartCallsBeginBackgroundTask() async throws {
    let backgroundTask = BackgroundTask.start(withName: "TestTask")

    let call = try fakeApplication.expectCall(
      methodName: "beginBackgroundTask",
      parameters: String?.self
    )
    #expect(call.parameters == "TestTask")
    #expect(backgroundTask.id != .invalid)
    #expect(fakeApplication.activeTaskCount == 1)

    backgroundTask.end()
  }

  @Test("that starting a background task returns a valid task identifier")
  func testStartReturnsValidIdentifier() async throws {
    let backgroundTask = BackgroundTask.start(withName: "TestTask")

    #expect(backgroundTask.id != .invalid)
    #expect(backgroundTask.id.rawValue > 0)

    backgroundTask.end()
  }

  @Test("that task name is preserved")
  func testTaskNameIsPreserved() async throws {
    let taskName = "MyCustomTaskName"
    let backgroundTask = BackgroundTask.start(withName: taskName)

    #expect(backgroundTask.name == taskName)

    backgroundTask.end()
  }

  // MARK: - End Tests

  @Test("that ending a background task calls endBackgroundTask")
  func testEndCallsEndBackgroundTask() async throws {
    let backgroundTask = BackgroundTask.start(withName: "TestTask")
    fakeApplication.clearAllCalls()

    backgroundTask.end()

    let call = try fakeApplication.expectCall(
      methodName: "endBackgroundTask",
      parameters: Int.self
    )
    #expect(call.parameters > 0)
    #expect(backgroundTask.id == .invalid)
    #expect(fakeApplication.activeTaskCount == 0)
  }

  @Test("that ending a task twice only calls endBackgroundTask once")
  func testEndingTwiceOnlyCallsOnce() async throws {
    let backgroundTask = BackgroundTask.start(withName: "TestTask")
    fakeApplication.clearAllCalls()

    backgroundTask.end()
    backgroundTask.end()

    _ = try fakeApplication.expectCalls(methodName: "endBackgroundTask", count: 1)
  }

  @Test("that ending sets id to invalid")
  func testEndSetsIdToInvalid() async throws {
    let backgroundTask = BackgroundTask.start(withName: "TestTask")
    #expect(backgroundTask.id != .invalid)

    backgroundTask.end()
    #expect(backgroundTask.id == .invalid)
  }

  // MARK: - Expiration Handler Tests

  @Test("that expiration handler ends the task")
  func testExpirationHandlerEndsTask() async throws {
    let backgroundTask = BackgroundTask.start(withName: "TestTask")
    let taskId = backgroundTask.id
    #expect(taskId != .invalid)
    #expect(fakeApplication.hasActiveTask(identifier: taskId))

    fakeApplication.clearAllCalls()

    fakeApplication.expireTask(taskId)

    let call = try fakeApplication.expectCall(
      methodName: "endBackgroundTask",
      parameters: Int.self
    )
    #expect(call.parameters == taskId.rawValue)
    #expect(backgroundTask.id == .invalid)
  }

  @Test("that expiration handler handles already invalid task gracefully")
  func testExpirationHandlerHandlesAlreadyInvalidTask() async throws {
    let backgroundTask = BackgroundTask.start(withName: "TestTask")
    let taskId = backgroundTask.id

    backgroundTask.end()
    #expect(backgroundTask.id == .invalid)

    fakeApplication.clearAllCalls()

    fakeApplication.expireTask(taskId)

    try fakeApplication.expectNoCall(methodName: "endBackgroundTask")
  }

  // MARK: - Multiple Tasks Tests

  @Test("that multiple background tasks can run concurrently")
  func testMultipleTasksCanRunConcurrently() async throws {
    let task1 = BackgroundTask.start(withName: "Task1")
    let task2 = BackgroundTask.start(withName: "Task2")
    let task3 = BackgroundTask.start(withName: "Task3")

    #expect(task1.id != task2.id)
    #expect(task2.id != task3.id)
    #expect(task1.id != task3.id)
    #expect(fakeApplication.activeTaskCount == 3)

    task1.end()
    #expect(fakeApplication.activeTaskCount == 2)

    task2.end()
    #expect(fakeApplication.activeTaskCount == 1)

    task3.end()
    #expect(fakeApplication.activeTaskCount == 0)
  }

  @Test("that expiring all tasks ends all active tasks")
  func testExpireAllTasksEndsAllActiveTasks() async throws {
    let task1 = BackgroundTask.start(withName: "Task1")
    let task2 = BackgroundTask.start(withName: "Task2")

    #expect(fakeApplication.activeTaskCount == 2)
    #expect(task1.id != .invalid)
    #expect(task2.id != .invalid)

    fakeApplication.expireAllTasks()

    #expect(fakeApplication.activeTaskCount == 0)
    #expect(task1.id == .invalid)
    #expect(task2.id == .invalid)
  }

  // MARK: - Default Name Tests

  @Test("that default function name is used when no name provided")
  func testDefaultFunctionNameIsUsed() async throws {
    let backgroundTask = BackgroundTask.start()

    let call = try fakeApplication.expectCall(
      methodName: "beginBackgroundTask",
      parameters: String?.self
    )
    #expect(call.parameters == "testDefaultFunctionNameIsUsed()")

    backgroundTask.end()
  }
}
