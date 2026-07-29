// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation

typealias NotificationSequence =
  @Sendable (_ name: Notification.Name) -> any AsyncSequence<Notification, Never>

protocol NotificationObserving: Sendable {
  @discardableResult
  func observe(
    _ name: Notification.Name,
    using action: @escaping @Sendable () -> Void
  ) -> any NSObjectProtocol
}

struct NotificationObserver: NotificationObserving {
  fileprivate init() {}

  @discardableResult
  func observe(
    _ name: Notification.Name,
    using action: @escaping @Sendable () -> Void
  ) -> any NSObjectProtocol {
    NotificationCenter.default.addObserver(
      forName: name,
      object: nil,
      queue: nil
    ) { _ in
      action()
    }
  }
}

extension Container {
  var notifications: Factory<NotificationSequence> {
    Factory(self) { { name in NotificationCenter.default.notifications(named: name) } }
  }

  var notificationObserver: Factory<any NotificationObserving> {
    Factory(self) { NotificationObserver() }.scope(.cached)
  }
}
