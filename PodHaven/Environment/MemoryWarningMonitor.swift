// Copyright Justin Bishop, 2026

import FactoryKit
import Logging
import UIKit

extension Container {
  @MainActor var memoryWarningMonitor: Factory<MemoryWarningMonitor> {
    Factory(self) { MemoryWarningMonitor() }.scope(.cached)
  }
}

@MainActor final class MemoryWarningMonitor {
  private static let log = Log.as("MemoryWarningMonitor")
  private var task: Task<Void, Never>?

  fileprivate init() {}

  deinit { task?.cancel() }

  func start() {
    guard task == nil else { return }
    let warnings =
      Container.shared.notifications()(UIApplication.didReceiveMemoryWarningNotification)
    let alert = Container.shared.alert()
    task = Task(priority: Container.shared.taskPriority()(.utility)) {
      for await _ in warnings {
        guard !Task.isCancelled else { return }
        Self.log.warning("System memory warning received")
        if AppInfo.environment.allowsDiagnostics, AppInfo.myDevice {
          alert("Memory warning received")
        }
      }
    }
  }
}
