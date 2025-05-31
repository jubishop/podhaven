// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation

extension Container {
  var notifications: Factory<(_ name: Notification.Name) -> any AsyncSequence<Notification, Never>>
  {
    Factory(self) { { name in NotificationCenter.default.notifications(named: name) } }
  }
}
