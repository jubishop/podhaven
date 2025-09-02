// Copyright Justin Bishop, 2025

import Foundation
import UIKit

@MainActor final class BackgroundTask {
  private static let log = Log.as("BackgroundTask")

  let name: String
  var id: UIBackgroundTaskIdentifier = .invalid

  // MARK: - Start

  private init(withName name: String) {
    self.name = name
  }

  static func start(withName name: String = #function) -> BackgroundTask {
    Self.log.debug("start: \(name)")
    let backgroundTask = BackgroundTask(withName: name)
    backgroundTask.id = UIApplication.shared.beginBackgroundTask(withName: name) {
      guard backgroundTask.id != .invalid else {
        Self.log.warning("start: \(name) id invalid in expirationHandler?")
        return
      }
      Self.log.info("start: \(name) expirationHandler")
      UIApplication.shared.endBackgroundTask(backgroundTask.id)
      backgroundTask.id = .invalid
    }
    return backgroundTask
  }

  @discardableResult
  static func start<R: Sendable>(
    withName name: String = #function,
    _ operation: @Sendable () async throws -> R
  ) async rethrows -> R {
    let backgroundTask = BackgroundTask.start(withName: name)
    defer { backgroundTask.end() }
    return try await operation()
  }

  @discardableResult
  static func start<R: Sendable>(
    withName name: String = #function,
    _ operation: @Sendable () throws -> R
  ) rethrows -> R {
    let backgroundTask = BackgroundTask.start(withName: name)
    defer { backgroundTask.end() }
    return try operation()
  }

  // MARK: - End

  func end() {
    guard id != .invalid else {
      Self.log.notice("end: \(name) id invalid in end")
      return
    }
    Self.log.debug("end: \(name)")
    UIApplication.shared.endBackgroundTask(id)
    id = .invalid
  }

  deinit {
    Assert.precondition(
      id == .invalid,
      "BackgroundTask: \(name) deinitialized without end()?"
    )
  }
}
