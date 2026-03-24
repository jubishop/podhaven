// Copyright Justin Bishop, 2026

import BackgroundTasks
import Foundation

@testable import PodHaven

struct RecordedBGTaskRegistration: Sendable {
  let identifier: String
  let usesDefaultQueue: Bool
}

struct RecordedBGTaskRequest: Sendable {
  let identifier: String
  let earliestBeginDate: Date?
  let isProcessing: Bool
  let requiresNetworkConnectivity: Bool

  init(
    identifier: String,
    earliestBeginDate: Date? = nil,
    isProcessing: Bool = false,
    requiresNetworkConnectivity: Bool = false
  ) {
    self.identifier = identifier
    self.earliestBeginDate = earliestBeginDate
    self.isProcessing = isProcessing
    self.requiresNetworkConnectivity = requiresNetworkConnectivity
  }

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

  func makeRequest() -> BGTaskRequest {
    let request: BGTaskRequest
    if isProcessing {
      let processing = BGProcessingTaskRequest(identifier: identifier)
      processing.requiresNetworkConnectivity = requiresNetworkConnectivity
      processing.requiresExternalPower = false
      request = processing
    } else {
      request = BGAppRefreshTaskRequest(identifier: identifier)
    }
    request.earliestBeginDate = earliestBeginDate
    return request
  }
}

final class FakeBGTask: BGTaskHandling, Sendable {
  private let _expirationHandler = ThreadSafe<(@Sendable () -> Void)?>(nil)
  private let _completionResults = ThreadSafe<[Bool]>([])

  func setExpirationHandler(_ handler: @escaping @Sendable () -> Void) {
    _expirationHandler(handler)
  }

  func setTaskCompleted(success: Bool) {
    _completionResults { $0.append(success) }
  }

  var completionCount: Int { _completionResults().count }
  var completionResults: [Bool] { _completionResults() }
  var hasExpirationHandler: Bool { _expirationHandler() != nil }

  func expire() {
    _expirationHandler()?()
  }
}

final class FakeBGTaskScheduler: BGTaskScheduling, Sendable {
  private let _registrations = ThreadSafe<[RecordedBGTaskRegistration]>([])
  private let _submissions = ThreadSafe<[RecordedBGTaskRequest]>([])
  private let _pendingRequests = ThreadSafe<[String: RecordedBGTaskRequest]>([:])
  private let _launchHandlers = ThreadSafe<[String: @Sendable (any BGTaskHandling) -> Void]>([:])
  private let _pendingTaskRequestsCallCount = ThreadSafe<Int>(0)

  private let _registerResult = ThreadSafe<Bool>(true)
  private let _submitError = ThreadSafe<(any Error)?>(nil)
  private let _deliverPendingRequestsAsynchronously = ThreadSafe<Bool>(false)

  // MARK: - Protocol Methods

  @discardableResult
  func register(
    forTaskWithIdentifier identifier: String,
    using queue: DispatchQueue?,
    launchHandler: @escaping @Sendable (any BGTaskHandling) -> Void
  ) -> Bool {
    _registrations {
      $0.append(
        RecordedBGTaskRegistration(
          identifier: identifier,
          usesDefaultQueue: queue == nil
        )
      )
    }

    let registerResult = _registerResult()
    guard registerResult else { return false }

    _launchHandlers { $0[identifier] = launchHandler }
    return true
  }

  func submit(_ taskRequest: BGTaskRequest) throws {
    if let error = _submitError() { throw error }

    let recordedRequest = RecordedBGTaskRequest(from: taskRequest)
    _submissions { $0.append(recordedRequest) }
    _pendingRequests { $0[recordedRequest.identifier] = recordedRequest }
  }

  func getPendingTaskRequests(
    completionHandler: @escaping @Sendable ([BGTaskRequest]) -> Void
  ) {
    _pendingTaskRequestsCallCount { $0 += 1 }

    let pendingRequests = Array(_pendingRequests().values)
    if _deliverPendingRequestsAsynchronously() {
      DispatchQueue.global()
        .async {
          completionHandler(pendingRequests.map { $0.makeRequest() })
        }
      return
    }

    completionHandler(pendingRequests.map { $0.makeRequest() })
  }

  // MARK: - Getters

  var registrations: [RecordedBGTaskRegistration] { _registrations() }
  var submissions: [RecordedBGTaskRequest] { _submissions() }
  var pendingIdentifiers: Set<String> { Set(_pendingRequests().keys) }
  var pendingTaskRequestsCallCount: Int { _pendingTaskRequestsCallCount() }

  // MARK: - Setters

  func setRegisterResult(_ result: Bool) {
    _registerResult(result)
  }

  func setSubmitError(_ error: (any Error)?) {
    _submitError { $0 = error }
  }

  func setPendingIdentifiers(_ identifiers: Set<String>) {
    _pendingRequests {
      $0 = Dictionary(
        uniqueKeysWithValues: identifiers.map {
          ($0, RecordedBGTaskRequest(identifier: $0))
        }
      )
    }
  }

  func addPendingIdentifier(
    _ identifier: String,
    earliestBeginDate: Date? = nil,
    isProcessing: Bool = false,
    requiresNetworkConnectivity: Bool = false
  ) {
    _pendingRequests {
      $0[identifier] = RecordedBGTaskRequest(
        identifier: identifier,
        earliestBeginDate: earliestBeginDate,
        isProcessing: isProcessing,
        requiresNetworkConnectivity: requiresNetworkConnectivity
      )
    }
  }

  func setDeliverPendingRequestsAsynchronously(_ asyncDelivery: Bool) {
    _deliverPendingRequestsAsynchronously(asyncDelivery)
  }

  // MARK: - Test Helpers

  func launchTask(withIdentifier identifier: String) -> FakeBGTask? {
    guard let launchHandler = _launchHandlers()[identifier] else { return nil }

    _pendingRequests { $0.removeValue(forKey: identifier) }

    let task = FakeBGTask()
    launchHandler(task)
    return task
  }

  func reset() {
    _registrations { $0.removeAll() }
    _submissions { $0.removeAll() }
    _pendingRequests { $0.removeAll() }
    _launchHandlers { $0.removeAll() }
    _pendingTaskRequestsCallCount(0)
    _registerResult(true)
    _submitError { $0 = nil }
    _deliverPendingRequestsAsynchronously(false)
  }
}
