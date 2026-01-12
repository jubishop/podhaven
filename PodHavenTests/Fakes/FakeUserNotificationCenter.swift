// Copyright Justin Bishop, 2025

import Foundation
import UserNotifications

@testable import PodHaven

struct RecordedNotificationRequest: Sendable {
  let identifier: String
  let title: String
  let body: String
  let hasSound: Bool

  init(from request: UNNotificationRequest) {
    self.identifier = request.identifier
    self.title = request.content.title
    self.body = request.content.body
    self.hasSound = request.content.sound != nil
  }
}

struct FakeUserNotificationCenter: NotifyingCenter {
  private let _authorizationStatus = ThreadSafe<UNAuthorizationStatus>(.authorized)
  private let _requestAuthorizationResult = ThreadSafe<Bool>(true)
  private let _requestAuthorizationError = ThreadSafe<(any Error)?>(nil)

  private let _addedRequests = ThreadSafe<[RecordedNotificationRequest]>([])
  private let _requestAuthorizationCalls = ThreadSafe<[UNAuthorizationOptions]>([])

  // MARK: - Public Protocol Methods

  func add(_ request: UNNotificationRequest) async throws {
    let recorded = RecordedNotificationRequest(from: request)
    _addedRequests { $0.append(recorded) }
  }

  func authorizationStatus() async -> UNAuthorizationStatus {
    _authorizationStatus()
  }

  func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
    _requestAuthorizationCalls { $0.append(options) }
    if let error = _requestAuthorizationError() {
      throw error
    }
    return _requestAuthorizationResult()
  }

  // MARK: - Getters

  var addedRequests: [RecordedNotificationRequest] { _addedRequests() }
  var requestAuthorizationCalls: [UNAuthorizationOptions] { _requestAuthorizationCalls() }

  // MARK: - Setters

  func setAuthorizationStatus(_ status: UNAuthorizationStatus) {
    _authorizationStatus(status)
  }

  func setRequestAuthorizationResult(_ result: Bool) {
    _requestAuthorizationResult(result)
  }

  func setRequestAuthorizationError(_ error: (any Error)?) {
    _requestAuthorizationError { $0 = error }
  }

  func clearAllCalls() {
    _addedRequests { $0.removeAll() }
    _requestAuthorizationCalls { $0.removeAll() }
  }
}
