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

final class Notifier: Sendable {
  private let streamAndContinuations = Mutex<
    [Notification.Name: (AsyncStream<Notification>, AsyncStream<Notification>.Continuation)]
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

  private func streamAndContinuation(for name: Notification.Name) -> (
    AsyncStream<Notification>, AsyncStream<Notification>.Continuation
  ) {
    streamAndContinuations.withLock { dict in
      if let (stream, continuation) = dict[name] {
        return (stream, continuation)
      }

      let (stream, continuation) = AsyncStream.makeStream(of: Notification.self)
      dict[name] = (stream, continuation)
      return (stream, continuation)
    }
  }
}
