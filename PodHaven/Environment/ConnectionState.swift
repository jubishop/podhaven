// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Network

extension Container {
  var connectionState: Factory<ConnectionState> {
    Factory(self) { ConnectionState() }.scope(.cached)
  }
}

final class ConnectionState: Sendable {
  var currentPath: NWPath { _currentPath() }

  private let _currentPath: ThreadSafe<NWPath>

  fileprivate init() {
    let monitor = NWPathMonitor()

    _currentPath = ThreadSafe<NWPath>(monitor.currentPath)

    monitor.pathUpdateHandler = { [weak self] path in
      guard let self else { return }
      _currentPath(path)
    }

    monitor.start(queue: DispatchQueue(label: "podhaven.connection.state"))
  }
}
