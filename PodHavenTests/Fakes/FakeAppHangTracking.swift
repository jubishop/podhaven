// Copyright Justin Bishop, 2026

@testable import PodHaven

final class FakeAppHangTracking: AppHangTracking {
  enum State: Sendable {
    case reporting
    case paused
  }

  // Sentry reports detected hangs until it is paused.
  private let current = ThreadSafe(State.reporting)

  var state: State { current() }

  func pause() { current(.paused) }
  func resume() { current(.reporting) }
}
