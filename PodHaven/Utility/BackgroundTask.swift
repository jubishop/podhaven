// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Logging
import UIKit

@MainActor final class BackgroundTask {
  private static var application: any ApplicationProviding { Container.shared.uiApplication() }

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
    backgroundTask.id = application.beginBackgroundTask(withName: name) {
      guard backgroundTask.id != .invalid else {
        Self.log.warning("start: \(name) id invalid in expirationHandler?")
        return
      }
      Self.log.info("start: \(name) expirationHandler")
      Self.application.endBackgroundTask(backgroundTask.id)
      backgroundTask.id = .invalid
    }
    return backgroundTask
  }

  // MARK: - End

  func end() {
    guard id != .invalid else {
      Self.log.info("end: \(name) id invalid in end")
      return
    }
    Self.log.debug("end: \(name)")
    Self.application.endBackgroundTask(id)
    id = .invalid
  }

  deinit {
    Assert.precondition(
      id == .invalid,
      "BackgroundTask: \(name) deinitialized without end()?"
    )
  }
}
