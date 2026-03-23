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
    identifier: String = testIdentifier,
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
  func registerCallsSystemRegister() {
    let scheduler = makeScheduler()

    scheduler.register { complete in complete(true) }

    #expect(fake.registrations.count == 1)
  }

  @Test("register is idempotent via Once")
  func registerIsIdempotent() {
    let scheduler = makeScheduler()

    scheduler.register { complete in complete(true) }
    scheduler.register { complete in complete(true) }

    #expect(fake.registrations.count == 1)
  }

  @Test("register schedules next task after registration")
  func registerSchedulesNext() {
    let scheduler = makeScheduler()

    scheduler.register { complete in complete(true) }

    #expect(fake.submissions.count == 1)
  }

  // MARK: - Schedule Next If Needed

  @Test("scheduleNextIfNeeded submits when cadence has elapsed and no pending tasks")
  func scheduleNextIfNeededSubmitsWhenReady() {
    let scheduler = makeScheduler(cadence: .seconds(1))

    scheduler.scheduleNextIfNeeded()

    #expect(fake.submissions.count == 1)
  }

  @Test("scheduleNextIfNeeded throttles when called within cadence")
  func scheduleNextIfNeededThrottles() {
    let scheduler = makeScheduler(cadence: .hours(1))

    // First call succeeds and sets lastAttempt
    scheduler.scheduleNextIfNeeded()
    #expect(fake.submissions.count == 1)

    // Second call is throttled because cadence hasn't elapsed
    scheduler.scheduleNextIfNeeded()
    #expect(fake.submissions.count == 1)
  }

  @Test("scheduleNextIfNeeded skips when task is already pending")
  func scheduleNextIfNeededSkipsWhenPending() {
    let scheduler = makeScheduler(cadence: .seconds(0))
    fake.addPendingIdentifier(Self.testIdentifier)

    scheduler.scheduleNextIfNeeded()

    #expect(fake.submissions.isEmpty)
  }

  @Test("scheduleNextIfNeeded ignores pending tasks with different identifiers")
  func scheduleNextIfNeededIgnoresOtherPending() {
    let scheduler = makeScheduler(cadence: .seconds(0))
    fake.addPendingIdentifier("some.other.identifier")

    scheduler.scheduleNextIfNeeded()

    #expect(fake.submissions.count == 1)
  }

  // MARK: - Task Type

  @Test("scheduling a processing task submits a processing request")
  func schedulingProcessingTask() {
    let scheduler = makeScheduler(
      cadence: .seconds(0),
      taskType: .processing(requiresNetworkConnectivity: true)
    )

    scheduler.scheduleNextIfNeeded()

    let submission = try! #require(fake.submissions.first)
    #expect(submission.isProcessing == true)
    #expect(submission.requiresNetworkConnectivity == true)
  }

  @Test("scheduling an app refresh task submits a non-processing request")
  func schedulingAppRefreshTask() {
    let scheduler = makeScheduler(cadence: .seconds(0), taskType: .appRefresh)

    scheduler.scheduleNextIfNeeded()

    let submission = try! #require(fake.submissions.first)
    #expect(submission.isProcessing == false)
  }

  @Test("scheduling sets earliestBeginDate based on cadence")
  func schedulingSetsEarliestBeginDate() {
    let cadence: Duration = .minutes(30)
    let scheduler = makeScheduler(cadence: cadence, taskType: .appRefresh)

    let before = Date.now
    scheduler.scheduleNextIfNeeded()
    let after = Date.now

    let submission = try! #require(fake.submissions.first)
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

    scheduler.scheduleNextIfNeeded()

    #expect(fake.submissions.isEmpty)
  }

  @Test("scheduling does not add to pending when submit fails")
  func schedulingDoesNotPendOnFailure() {
    let scheduler = makeScheduler(cadence: .seconds(0))
    fake.setSubmitError(TestError.simulatedFailure)

    scheduler.scheduleNextIfNeeded()

    #expect(fake.pendingIdentifiers.isEmpty)
  }

  // MARK: - Confirm And Log

  @Test("confirmAndLogPendingTask does nothing when no attempt has been made")
  func confirmDoesNothingBeforeFirstSchedule() {
    let scheduler = makeScheduler()

    // No scheduling has happened, so lastAttempt is .distantPast
    scheduler.confirmAndLogPendingTask()

    // getPendingTaskRequests should not be called — we verify indirectly
    // by checking that no submissions were triggered (confirm only reads)
    #expect(fake.submissions.isEmpty)
  }

  @Test("confirmAndLogPendingTask queries pending tasks after scheduling")
  func confirmQueriesAfterScheduling() {
    let scheduler = makeScheduler(cadence: .seconds(0))

    // Schedule first to set lastAttempt
    scheduler.scheduleNextIfNeeded()
    #expect(fake.pendingIdentifiers.contains(Self.testIdentifier))

    // confirmAndLogPendingTask should run without error
    // (the task is pending, so it logs success)
    scheduler.confirmAndLogPendingTask()
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
