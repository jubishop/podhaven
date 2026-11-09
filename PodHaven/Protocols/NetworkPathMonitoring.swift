// Copyright Justin Bishop, 2026

import Foundation

protocol NetworkPathDescribing: Sendable {
  var isConstrained: Bool { get }
  var isUltraConstrained: Bool { get }
  var isExpensive: Bool { get }
}

protocol NetworkPathMonitoring: Sendable {
  func start(
    queue: DispatchQueue,
    pathUpdateHandler: @escaping @Sendable (any NetworkPathDescribing) -> Void
  )
}
