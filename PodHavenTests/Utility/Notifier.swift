// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation

@testable import PodHaven

extension Container {
  var notifier: Factory<Notifier> {
    Factory(self) { Notifier() }.scope(.cached)
  }
}

class Notifier {
  private var streamAndContinuations:
    [Notification.Name: (AsyncStream<Notification>, AsyncStream<Notification>.Continuation)] = [:]

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
    if let (stream, continuation) = streamAndContinuations[name] {
      return (stream, continuation)
    }

    let (stream, continuation) = AsyncStream.makeStream(of: Notification.self)
    streamAndContinuations[name] = (stream, continuation)
    return (stream, continuation)
  }
}
