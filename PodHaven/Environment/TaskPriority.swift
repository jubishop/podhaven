// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation

extension Container {
  // Injectable task priority so tests can return nil (inherit from parent),
  // preventing cooperative thread pool starvation when test suites run
  // concurrently in CI and hundreds of .utility tasks compete for scheduling.
  var taskPriority: Factory<@Sendable (TaskPriority?) -> TaskPriority?> {
    Factory(self) { { $0 } }.scope(.cached)
  }
}
