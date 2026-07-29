// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Synchronization

@testable import PodHaven

extension Container {
  var notifier: Factory<Notifier> {
    Factory(self) { Notifier() }.scope(.cached)
  }
}

final class Notifier: NotificationObserving, Sendable {
  private let streamAndContinuations = ThreadSafe<
    [Notification.Name: (AsyncStream<Notification>, AsyncStream<Notification>.Continuation)]
  >([:])
  private let observers = ThreadSafe<
    [Notification.Name: [@Sendable () -> Void]]
  >([:])

  fileprivate init() {}

  func stream(for name: Notification.Name) -> AsyncStream<Notification> {
    let (stream, _) = streamAndContinuation(for: name)
    return stream
  }

  func continuation(for name: Notification.Name) -> AsyncStream<Notification>.Continuation {
    let (_, continuation) = streamAndContinuation(for: name)
    return continuation
  }

  @discardableResult
  func observe(
    _ name: Notification.Name,
    using action: @escaping @Sendable () -> Void
  ) -> any NSObjectProtocol {
    observers { observers in
      observers[name, default: []].append(action)
    }
    return NSObject()
  }

  func post(_ name: Notification.Name) {
    for observer in observers()[name] ?? [] {
      observer()
    }
  }

  private func streamAndContinuation(for name: Notification.Name) -> (
    AsyncStream<Notification>, AsyncStream<Notification>.Continuation
  ) {
    streamAndContinuations { dict in
      if let (stream, continuation) = dict[name] {
        return (stream, continuation)
      }

      let (stream, continuation) = AsyncStream.makeStream(of: Notification.self)
      dict[name] = (stream, continuation)
      return (stream, continuation)
    }
  }
}
