// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation

typealias NotificationSequence =
  @Sendable (_ name: Notification.Name) -> any AsyncSequence<Notification, Never>

extension Container {
  var notifications: Factory<NotificationSequence> {
    Factory(self) { { name in NotificationCenter.default.notifications(named: name) } }
  }
}
