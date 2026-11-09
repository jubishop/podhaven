// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Network

extension Container {
  var connectionState: Factory<ConnectionState> {
    Factory(self) { ConnectionState() }.scope(.cached)
  }

  var networkPathMonitor: Factory<any NetworkPathMonitoring> {
    Factory(self) { NWPathMonitor() }
  }
}

struct ConnectionState: Sendable {
  struct Path: Sendable {
    let isConstrained: Bool
    let isExpensive: Bool
  }

  private let monitor: any NetworkPathMonitoring
  private let latestPath = AsyncLatch<Path>()

  fileprivate init() {
    monitor = Container.shared.networkPathMonitor()
    monitor.start(queue: DispatchQueue(label: "podhaven.connection.state")) {
      [latestPath] path in
      latestPath.close()
      latestPath.open(
        Path(
          isConstrained: path.isConstrained || path.isUltraConstrained,
          isExpensive: path.isExpensive
        )
      )
    }
  }

  // The path is unknown until the monitor's first update.
  func currentPath() async throws -> Path {
    try await latestPath.wait()
  }
}
