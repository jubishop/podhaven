// Copyright Justin Bishop, 2026

import FactoryKit
import Logging

extension Container {
  var appLauncher: Factory<AppLauncher> {
    Factory(self) { AppLauncher() }.scope(.cached)
  }
}

struct AppLauncher: Sendable {
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.cachePurger) private var cachePurger
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.refreshScheduler) private var refreshScheduler
  @DynamicInjected(\.stateManager) private var stateManager
  @DynamicInjected(\.widgetSnapshotWriter) private var widgetSnapshotWriter

  private var userNotificationManager: UserNotificationManager {
    Container.shared.userNotificationManager()
  }

  private static let log = Log.as("AppLauncher")

  fileprivate init() {}

  // Minimum initialization for audio playback from a background launch.
  // Called from widget intents when the app may not have a foreground scene.
  func prepareForPlayback() async {
    guard Function.neverCalled() else { return }

    Self.log.info("Preparing for background audio playback")
    stateManager.start()
    widgetSnapshotWriter.start()
    await playManager.start()
  }

  // Full initialization for the foreground UI experience.
  // Called when the app scene becomes active.
  func prepareForForeground() async {
    guard Function.neverCalled() else { return }

    Self.log.info("Preparing for foreground")

    await AppInfo.finalizeEnvironment()
    guard !Task.isCancelled else { return }

    await userNotificationManager.initialize()
    guard !Task.isCancelled else { return }

    Self.log.debug("Device identifier is: \(AppInfo.deviceIdentifier)")
    Self.log.debug("My device?: \(AppInfo.myDevice)")
    Self.log.debug("Final environment is: \(AppInfo.environment)")
    Self.log.debug("Build version: \(AppInfo.version) (\(AppInfo.buildNumber))")

    // Ensure playback subsystems are started (no-op if already done by an intent)
    stateManager.start()
    widgetSnapshotWriter.start()

    guard AppInfo.environment != .testing else { return }

    await playManager.start()
    guard !Task.isCancelled else { return }

    cacheManager.start()
    refreshScheduler.start()
    cachePurger.start()
  }
}
