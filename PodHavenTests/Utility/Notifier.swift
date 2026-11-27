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

// Gives each stream(for:) call its own stream and, like NotificationCenter,
// delivers each yielded notification to every live one. A notification yielded
// while its name has no live stream goes to the next one requested for it; a
// cancelled task's request gets a stream that has already ended.
final class Notifier: NotificationObserving, Sendable {
  struct Continuation: Sendable {
    fileprivate let name: Notification.Name
    fileprivate let notifier: Notifier

    func yield(_ notification: sending Notification) {
      notifier.deliver(notification, to: name)
    }
  }

  private struct Subscription {
    let id = UUID()
    let stream: AsyncStream<Notification>
    let continuation: AsyncStream<Notification>.Continuation
  }

  private struct Channel {
    var streams: [UUID: AsyncStream<Notification>.Continuation] = [:]
    var reserved: Subscription?
  }

  private let channels = ThreadSafe<[Notification.Name: Channel]>([:])
  private let observers = ThreadSafe<
    [Notification.Name: [@Sendable () -> Void]]
  >([:])

  fileprivate init() {}

  func stream(for name: Notification.Name) -> AsyncStream<Notification> {
    guard !Task.isCancelled else { return AsyncStream { $0.finish() } }

    return channels { channels in
      let subscription = channels[name]?.reserved ?? makeSubscription(for: name)
      channels[name, default: Channel()].reserved = nil
      channels[name, default: Channel()].streams[subscription.id] = subscription.continuation
      return subscription.stream
    }
  }

  func continuation(for name: Notification.Name) -> Continuation {
    Continuation(name: name, notifier: self)
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

  private func deliver(_ notification: sending Notification, to name: Notification.Name) {
    nonisolated(unsafe) let notification = notification
    let continuations = channels { channels in
      let streams = Array(channels[name, default: Channel()].streams.values)
      guard streams.isEmpty else { return streams }

      let reserved = channels[name]?.reserved ?? makeSubscription(for: name)
      channels[name, default: Channel()].reserved = reserved
      return [reserved.continuation]
    }
    for continuation in continuations {
      continuation.yield(notification)
    }
  }

  private func makeSubscription(for name: Notification.Name) -> Subscription {
    let (stream, continuation) = AsyncStream.makeStream(of: Notification.self)
    let subscription = Subscription(stream: stream, continuation: continuation)
    continuation.onTermination = { [weak self, id = subscription.id] _ in
      guard let self else { return }
      channels { channels in
        channels[name]?.streams[id] = nil
      }
    }
    return subscription
  }
}
