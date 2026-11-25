// Copyright Justin Bishop, 2026

import Foundation
import Testing

@testable import PodHaven

struct FakeNetworkPath: NetworkPathDescribing, CustomTestStringConvertible {
  var isSatisfied = true
  var isConstrained = false
  var isUltraConstrained = false
  var isExpensive = false

  var testDescription: String {
    "satisfied: \(isSatisfied), constrained: \(isConstrained), ultraConstrained: \(isUltraConstrained), expensive: \(isExpensive)"
  }
}

// Like NWPathMonitor, delivers an initial path on the monitor's queue after
// start unless a test withholds it.
final class FakeNetworkPathMonitor: NetworkPathMonitoring {
  private struct State: Sendable {
    var initialPath: FakeNetworkPath? = FakeNetworkPath()
    var pathUpdateHandler: (@Sendable (any NetworkPathDescribing) -> Void)?
  }

  private let state = ThreadSafe(State())
  private let started = AsyncLatch<Void>()

  func start(
    queue: DispatchQueue,
    pathUpdateHandler: @escaping @Sendable (any NetworkPathDescribing) -> Void
  ) {
    let initialPath = state { state in
      state.pathUpdateHandler = pathUpdateHandler
      return state.initialPath
    }
    started.open()
    guard let initialPath else { return }

    queue.async { pathUpdateHandler(initialPath) }
  }

  // MARK: - Test Helpers

  func withholdInitialPath() {
    state { $0.initialPath = nil }
  }

  func waitForStart() async throws {
    try await started.wait()
  }

  func update(_ path: FakeNetworkPath) {
    guard let pathUpdateHandler = state({ $0.pathUpdateHandler }) else {
      Issue.record("Network path updated before the monitor started")
      return
    }

    pathUpdateHandler(path)
  }
}
