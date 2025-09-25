// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Network

extension Container {
  var connectionState: Factory<ConnectionState> {
    Factory(self) { ConnectionState() }.scope(.cached)
  }
}

actor ConnectionState {
  private let monitor = NWPathMonitor()
  private let queue = DispatchQueue(label: "podhaven.connectivity.monitor")
  private var currentPath: NWPath

  fileprivate init() {
    currentPath = monitor.currentPath
  }

  func start() async {
    Assert.neverCalled()

    monitor.pathUpdateHandler = { [weak self] path in
      guard let self else { return }
      Task { await setCurrentPath(path) }
    }

    monitor.start(queue: queue)
  }

  private func setCurrentPath(_ path: NWPath) {
    self.currentPath = path
  }
}
