// Copyright Justin Bishop, 2026

import BackgroundTasks
import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of BackgroundTaskScheduler tests", .container)
struct BackgroundTaskSchedulerTests {
  @DynamicInjected(\.bgTaskScheduler) private var bgTaskScheduler

  private var fake: FakeBGTaskScheduler { bgTaskScheduler as! FakeBGTaskScheduler }

  private static let testIdentifier = "test.bgScheduler"

  private func makeScheduler(
    identifier: String = Self.testIdentifier,
    cadence: Duration = .hours(1),
    taskType: BackgroundTaskType = .appRefresh
  ) -> BackgroundTaskScheduler {
    BackgroundTaskScheduler(
      identifier: identifier,
      cadence: cadence,
      taskType: taskType
    )
  }

  // MARK: - Register

  @Test("register calls BGTaskScheduler.register with the correct identifier")
  func registerCallsSystemRegisterWithCorrectIdentifier() throws {
    let scheduler = makeScheduler()

    scheduler.register { complete in complete(true) }

    let registration = try #require(fake.registrations.first)
    #expect(fake.registrations.count == 1)
    #expect(registration.identifier == Self.testIdentifier)
    #expect(registration.usesDefaultQueue == true)
  }

  @Test("register is idempotent via Once")
  func registerIsIdempotent() {
    let scheduler = makeScheduler()

    scheduler.register { complete in complete(true) }
    scheduler.register { complete in complete(true) }

    #expect(fake.registrations.count == 1)
  }

  @Test("register schedules next task after registration")
  func registerSchedulesNext() throws {
    let scheduler = makeScheduler()

    scheduler.register { complete in complete(true) }

    let submission = try #require(fake.submissions.first)
    #expect(fake.submissions.count == 1)
    #expect(submission.identifier == Self.testIdentifier)
  }

  @Test("register does not schedule tasks when registration fails")
  func registerDoesNotScheduleOnFailure() {
    let scheduler = makeScheduler()
    fake.setRegisterResult(false)

    scheduler.register { complete in complete(true) }

    #expect(fake.registrations.count == 1)
    #expect(fake.submissions.isEmpty)
    if case .some = fake.launchTask(withIdentifier: Self.testIdentifier) {
      Issue.record("Failed registrations should not install a launch handler")
    }
  }

  @Test("launching a registered task runs the execution task and reschedules")
  func launchingRegisteredTaskRunsExecutionTaskAndReschedules() async throws {
    let scheduler = makeScheduler(cadence: .seconds(0))
    let executionRan = ActorContainer<Bool>()

    scheduler.register { complete in
      await executionRan.set(true)
      complete(true)
    }

    #expect(fake.submissions.count == 1)

    let task = try #require(fake.launchTask(withIdentifier: Self.testIdentifier))
    #expect(task.hasExpirationHandler == true)

    try await executionRan.waitForEqual(to: true)
    try await Wait.until(
      { task.completionResults == [true] },
      {
        """
        Expected launch task to complete once with success, got \(task.completionResults)
        """
      }
    )
    try await Wait.until(
      { fake.submissions.count == 2 },
      { "Expected reschedule after launch, got \(fake.submissions.count) submissions" }
    )

    #expect(fake.pendingIdentifiers.contains(Self.testIdentifier))
  }

  @Test("expiration cancels running work and completes the task once")
  func expirationCancelsRunningWorkAndCompletesOnce() async throws {
    let scheduler = makeScheduler(cadence: .seconds(0))
    let executionStarted = ActorContainer<Bool>()
    let executionCancelled = ActorContainer<Bool>()

    scheduler.register { _ in
      await executionStarted.set(true)
      while !Task.isCancelled {
        await Task.yield()
      }
      await executionCancelled.set(true)
    }

    let task = try #require(fake.launchTask(withIdentifier: Self.testIdentifier))

    try await executionStarted.waitForEqual(to: true)

    task.expire()
    task.expire()

    try await executionCancelled.waitForEqual(to: true)
    try await Wait.until(
      { task.completionResults == [false] },
      { "Expected expiration to complete once with failure, got \(task.completionResults)" }
    )

    #expect(task.completionCount == 1)
  }

  @Test("completion remains idempotent after execution completes")
  func completionRemainsIdempotentAfterExecutionCompletes() async throws {
    let scheduler = makeScheduler(cadence: .seconds(0))

    scheduler.register { complete in
      complete(true)
      complete(false)
    }

    let task = try #require(fake.launchTask(withIdentifier: Self.testIdentifier))

    try await Wait.until(
      { task.completionResults == [true] },
      { "Expected task to complete once with success, got \(task.completionResults)" }
    )

    task.expire()

    #expect(task.completionCount == 1)
    #expect(task.completionResults == [true])
  }

  // MARK: - Schedule Next If Needed

  @Test("scheduleNext submits when cadence has elapsed and no pending tasks")
  func scheduleNextSubmitsWhenReady() {
    let scheduler = makeScheduler(cadence: .seconds(1))

    scheduler.scheduleNext()

    #expect(fake.submissions.count == 1)
  }

  @Test("scheduleNext submits when pending requests are returned asynchronously")
  func scheduleNextSupportsAsyncPendingRequestLookup() async throws {
    let scheduler = makeScheduler(cadence: .seconds(0))
    fake.setDeliverPendingRequestsAsynchronously(true)

    scheduler.scheduleNext()

    try await Wait.until(
      { fake.submissions.count == 1 },
      { "Expected async pending lookup to schedule a request" }
    )
  }

  @Test("scheduleNext throttles when called within cadence")
  func scheduleNextThrottles() {
    let scheduler = makeScheduler(cadence: .hours(1))

    scheduler.scheduleNext()
    #expect(fake.submissions.count == 1)

    scheduler.scheduleNext()
    #expect(fake.submissions.count == 1)
  }

  @Test("scheduleNext skips when task is already pending")
  func scheduleNextSkipsWhenPending() {
    let scheduler = makeScheduler(cadence: .seconds(0))
    fake.addPendingIdentifier(Self.testIdentifier)

    scheduler.scheduleNext()

    #expect(fake.submissions.isEmpty)
  }

  @Test("scheduleNext ignores pending tasks with different identifiers")
  func scheduleNextIgnoresOtherPending() {
    let scheduler = makeScheduler(cadence: .seconds(0))
    fake.addPendingIdentifier("some.other.identifier")

    scheduler.scheduleNext()

    #expect(fake.submissions.count == 1)
  }

  // MARK: - Task Type

  @Test("scheduling a processing task submits a processing request")
  func schedulingProcessingTask() throws {
    let scheduler = makeScheduler(
      cadence: .seconds(0),
      taskType: .processing(requiresNetworkConnectivity: true)
    )

    scheduler.scheduleNext()

    let submission = try #require(fake.submissions.first)
    #expect(submission.isProcessing == true)
    #expect(submission.requiresNetworkConnectivity == true)
  }

  @Test("scheduling an app refresh task submits a non-processing request")
  func schedulingAppRefreshTask() throws {
    let scheduler = makeScheduler(cadence: .seconds(0), taskType: .appRefresh)

    scheduler.scheduleNext()

    let submission = try #require(fake.submissions.first)
    #expect(submission.isProcessing == false)
  }

  @Test("scheduling sets earliestBeginDate based on cadence")
  func schedulingSetsEarliestBeginDate() throws {
    let cadence: Duration = .minutes(30)
    let scheduler = makeScheduler(cadence: cadence, taskType: .appRefresh)

    let before = Date.now
    scheduler.scheduleNext()
    let after = Date.now

    let submission = try #require(fake.submissions.first)
    if let beginDate = submission.earliestBeginDate {
      let expectedEarliest = before.addingTimeInterval(cadence.asTimeInterval)
      let expectedLatest = after.addingTimeInterval(cadence.asTimeInterval)
      #expect(beginDate >= expectedEarliest)
      #expect(beginDate <= expectedLatest)
    } else {
      Issue.record("earliestBeginDate should not be nil")
    }
  }

  // MARK: - Submit Error Handling

  @Test("scheduling handles submit error gracefully")
  func schedulingHandlesSubmitError() {
    let scheduler = makeScheduler(cadence: .seconds(0))
    fake.setSubmitError(TestError.simulatedFailure)

    scheduler.scheduleNext()

    #expect(fake.submissions.isEmpty)
  }

  @Test("scheduling does not add to pending when submit fails")
  func schedulingDoesNotPendOnFailure() {
    let scheduler = makeScheduler(cadence: .seconds(0))
    fake.setSubmitError(TestError.simulatedFailure)

    scheduler.scheduleNext()

    #expect(fake.pendingIdentifiers.isEmpty)
  }

  // MARK: - BackgroundTaskType

  @Test(
    "makeRequest creates the correct request type",
    arguments: [
      (BackgroundTaskType.appRefresh, false),
      (BackgroundTaskType.processing(requiresNetworkConnectivity: false), true),
      (BackgroundTaskType.processing(requiresNetworkConnectivity: true), true),
    ]
  )
  func makeRequestCreatesCorrectType(taskType: BackgroundTaskType, expectProcessing: Bool) {
    let request = taskType.makeRequest(identifier: "test.id")

    if expectProcessing {
      #expect(request is BGProcessingTaskRequest)
    } else {
      #expect(request is BGAppRefreshTaskRequest)
    }
  }

  @Test("processing request sets requiresNetworkConnectivity")
  func processingRequestSetsNetworkConnectivity() {
    let request = BackgroundTaskType.processing(requiresNetworkConnectivity: true)
      .makeRequest(identifier: "test.id")

    let processing = request as! BGProcessingTaskRequest
    #expect(processing.requiresNetworkConnectivity == true)
    #expect(processing.requiresExternalPower == false)
  }

  @Test("processing request without network does not require connectivity")
  func processingRequestWithoutNetwork() {
    let request = BackgroundTaskType.processing(requiresNetworkConnectivity: false)
      .makeRequest(identifier: "test.id")

    let processing = request as! BGProcessingTaskRequest
    #expect(processing.requiresNetworkConnectivity == false)
  }

  // MARK: - Format Pending Tasks

  @Test("formatPendingTasks formats processing requests")
  func formatPendingTasksProcessing() {
    let request = BGProcessingTaskRequest(identifier: "com.test.processing")
    let formatted = BackgroundTaskScheduler.formatPendingTasks([request])

    #expect(formatted.contains("com.test.processing"))
    #expect(formatted.contains("processing"))
  }

  @Test("formatPendingTasks formats refresh requests")
  func formatPendingTasksRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: "com.test.refresh")
    let formatted = BackgroundTaskScheduler.formatPendingTasks([request])

    #expect(formatted.contains("com.test.refresh"))
    #expect(formatted.contains("refresh"))
  }

  @Test("formatPendingTasks formats earliest begin date")
  func formatPendingTasksWithDate() {
    let request = BGAppRefreshTaskRequest(identifier: "com.test.dated")
    request.earliestBeginDate = Date.now
    let formatted = BackgroundTaskScheduler.formatPendingTasks([request])

    #expect(formatted.contains("com.test.dated"))
    #expect(!formatted.contains("none"))
  }

  @Test("formatPendingTasks shows none for nil date")
  func formatPendingTasksNilDate() {
    let request = BGAppRefreshTaskRequest(identifier: "com.test.nodate")
    let formatted = BackgroundTaskScheduler.formatPendingTasks([request])

    #expect(formatted.contains("none"))
  }

  @Test("formatPendingTasks handles empty list")
  func formatPendingTasksEmpty() {
    let formatted = BackgroundTaskScheduler.formatPendingTasks([])

    #expect(formatted.isEmpty)
  }
}
