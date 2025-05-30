// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation

extension Container {
  typealias Notifying = (_ name: Notification.Name) -> any AsyncSequence<Notification, Never>
  var notifications: Factory<Notifying> {
    Factory(self) { { name in NotificationCenter.default.notifications(named: name) } }
  }
}
