// Copyright Justin Bishop, 2026

import Foundation
import Network

extension NWPath: NetworkPathDescribing {}

extension NWPathMonitor: NetworkPathMonitoring {
  func start(
    queue: DispatchQueue,
    pathUpdateHandler: @escaping @Sendable (any NetworkPathDescribing) -> Void
  ) {
    self.pathUpdateHandler = { pathUpdateHandler($0) }
    start(queue: queue)
  }
}
