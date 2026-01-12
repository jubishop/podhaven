// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Network

extension Container {
  var connectionState: Factory<ConnectionState> {
    Factory(self) { ConnectionState() }.scope(.cached)
  }
}

struct ConnectionState: Sendable {
  var currentPath: NWPath { _currentPath() }

  private let _currentPath: ThreadSafe<NWPath>

  fileprivate init() {
    let monitor = NWPathMonitor()

    _currentPath = ThreadSafe<NWPath>(monitor.currentPath)

    monitor.pathUpdateHandler = { [_currentPath] path in
      _currentPath(path)
    }

    monitor.start(queue: DispatchQueue(label: "podhaven.connection.state"))
  }

  var isConstrained: Bool {
    currentPath.isConstrained || currentPath.isUltraConstrained
  }

  var isExpensive: Bool {
    currentPath.isExpensive
  }
}
