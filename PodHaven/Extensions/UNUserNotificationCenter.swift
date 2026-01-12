// Copyright Justin Bishop, 2025

import Foundation
import UserNotifications

extension UNUserNotificationCenter: NotifyingCenter {
  func authorizationStatus() async -> UNAuthorizationStatus {
    await notificationSettings().authorizationStatus
  }
}
