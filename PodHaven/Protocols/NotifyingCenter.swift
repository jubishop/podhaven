// Copyright Justin Bishop, 2025

import UserNotifications

protocol NotifyingCenter: Sendable {
  func add(_ request: UNNotificationRequest) async throws
  func authorizationStatus() async -> UNAuthorizationStatus
  func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
}
