// Copyright Justin Bishop, 2026

import Foundation
import UIKit

@testable import PodHaven

final class FakeApplication: ApplicationProviding, FakeCallable {
  nonisolated let callOrder = ThreadSafe<Int>(0)
  nonisolated let callsByType = ThreadSafe<[ObjectIdentifier: [any MethodCalling]]>([:])

  // MARK: - State

  var applicationState: UIApplication.State = .active

  private var nextTaskIdentifier: Int = 1
  private var activeTasks: [UIBackgroundTaskIdentifier: (@MainActor @Sendable () -> Void)?] = [:]

  var openedURLs: [URL] = []

  // MARK: - Background Tasks

  func beginBackgroundTask(
    withName taskName: String?,
    expirationHandler handler: (@MainActor @Sendable () -> Void)?
  ) -> UIBackgroundTaskIdentifier {
    recordCall(methodName: "beginBackgroundTask", parameters: taskName)

    let identifier = UIBackgroundTaskIdentifier(rawValue: nextTaskIdentifier)
    nextTaskIdentifier += 1
    activeTasks[identifier] = handler
    return identifier
  }

  func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier) {
    recordCall(methodName: "endBackgroundTask", parameters: identifier.rawValue)

    activeTasks.removeValue(forKey: identifier)
  }

  // MARK: - URL Opening

  func open(
    _ url: URL,
    options: [UIApplication.OpenExternalURLOptionsKey: Any],
    completionHandler completion: (@MainActor @Sendable (Bool) -> Void)?
  ) {
    recordCall(methodName: "open", parameters: url)

    openedURLs.append(url)
    completion?(true)
  }

  // MARK: - Test Helpers

  var activeTaskCount: Int {
    activeTasks.count
  }

  func hasActiveTask(identifier: UIBackgroundTaskIdentifier) -> Bool {
    activeTasks[identifier] != nil
  }

  func expireAllTasks() {
    for (identifier, handler) in activeTasks {
      handler?()
      activeTasks.removeValue(forKey: identifier)
    }
  }

  func expireTask(_ identifier: UIBackgroundTaskIdentifier) {
    guard let handler = activeTasks[identifier] else { return }
    handler?()
    activeTasks.removeValue(forKey: identifier)
  }
}
