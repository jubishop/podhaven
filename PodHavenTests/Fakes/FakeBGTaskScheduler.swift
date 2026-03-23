// Copyright Justin Bishop, 2026

import BackgroundTasks
import Foundation

@testable import PodHaven

struct RecordedBGTaskRegistration: Sendable {
  let identifier: String
}

struct RecordedBGTaskSubmission: Sendable {
  let identifier: String
  let earliestBeginDate: Date?
  let isProcessing: Bool
  let requiresNetworkConnectivity: Bool

  init(from request: BGTaskRequest) {
    self.identifier = request.identifier
    self.earliestBeginDate = request.earliestBeginDate
    if let processing = request as? BGProcessingTaskRequest {
      self.isProcessing = true
      self.requiresNetworkConnectivity = processing.requiresNetworkConnectivity
    } else {
      self.isProcessing = false
      self.requiresNetworkConnectivity = false
    }
  }
}

final class FakeBGTaskScheduler: BGTaskScheduling, Sendable {
  private let _registrations = ThreadSafe<[RecordedBGTaskRegistration]>([])
  private let _submissions = ThreadSafe<[RecordedBGTaskSubmission]>([])
  private let _pendingIdentifiers = ThreadSafe<Set<String>>([])

  private let _registerResult = ThreadSafe<Bool>(true)
  private let _submitError = ThreadSafe<(any Error)?>(nil)

  // MARK: - Protocol Methods

  @discardableResult
  func register(
    forTaskWithIdentifier identifier: String,
    using queue: DispatchQueue?,
    launchHandler: @escaping @Sendable (BGTask) -> Void
  ) -> Bool {
    _registrations { $0.append(RecordedBGTaskRegistration(identifier: identifier)) }
    return _registerResult()
  }

  func submit(_ taskRequest: BGTaskRequest) throws {
    if let error = _submitError() { throw error }
    _submissions { $0.append(RecordedBGTaskSubmission(from: taskRequest)) }
    _pendingIdentifiers { $0.insert(taskRequest.identifier) }
  }

  func getPendingTaskRequests(
    completionHandler: @escaping @Sendable ([BGTaskRequest]) -> Void
  ) {
    let requests = _pendingIdentifiers()
      .map {
        BGAppRefreshTaskRequest(identifier: $0) as BGTaskRequest
      }
    completionHandler(requests)
  }

  // MARK: - Getters

  var registrations: [RecordedBGTaskRegistration] { _registrations() }
  var submissions: [RecordedBGTaskSubmission] { _submissions() }
  var pendingIdentifiers: Set<String> { _pendingIdentifiers() }

  // MARK: - Setters

  func setRegisterResult(_ result: Bool) {
    _registerResult(result)
  }

  func setSubmitError(_ error: (any Error)?) {
    _submitError { $0 = error }
  }

  func setPendingIdentifiers(_ identifiers: Set<String>) {
    _pendingIdentifiers { $0 = identifiers }
  }

  func addPendingIdentifier(_ identifier: String) {
    _pendingIdentifiers { $0.insert(identifier) }
  }

  // MARK: - Test Helpers

  func reset() {
    _registrations { $0.removeAll() }
    _submissions { $0.removeAll() }
    _pendingIdentifiers { $0.removeAll() }
    _registerResult(true)
    _submitError { $0 = nil }
  }
}
