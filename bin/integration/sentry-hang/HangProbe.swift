// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Logging
import Sentry
import SwiftUI

private final class ProbeFileManager: FileManager, @unchecked Sendable {
  override func containerURL(forSecurityApplicationGroupIdentifier groupIdentifier: String) -> URL?
  {
    URL.documentsDirectory.appendingPathComponent("widget", isDirectory: true)
  }
}

private struct ProbeStore: KeyValueStore {
  let delay: TimeInterval
  let started: @Sendable () -> Void
  var allKeys: [String] { UserDefaults.standard.allKeys }
  func data(forKey key: String) -> Data? { UserDefaults.standard.data(forKey: key) }
  func string(forKey key: String) -> String? { UserDefaults.standard.string(forKey: key) }
  func removeObject(forKey key: String) { UserDefaults.standard.removeObject(forKey: key) }
  func set(_ value: Any?, forKey key: String) {
    started()
    Thread.sleep(forTimeInterval: delay)
    UserDefaults.standard.set(value, forKey: key)
  }
}

@main
struct HangProbe: App {
  nonisolated private static let log = Log.as("ControlledHangProbe")
  private let run = ProcessInfo.processInfo.environment["PODHAVEN_HANG_RUN"] ?? UUID().uuidString

  init() {
    Container.shared.fileManager.register { ProbeFileManager() }
    AppInfo.initializeEnvironment()
    do {
      try FileManager.default.createDirectory(
        at: WidgetInfo.recentLogFileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
    } catch {
      fatalError("Unable to prepare controlled widget directory: \(error)")
    }
    LoggingSystem.bootstrap { label in
      FileLogHandler(
        label: label,
        fileURL: AppInfo.recentLogFileURL,
        maxFileSizeBytes: AppInfo.recentLogMaxFileSizeBytes,
        targetFileSizeBytes: AppInfo.recentLogTargetFileSizeBytes,
        historyPolicy: .preservePreviousSession,
        writeSynchronously: { _ in false }
      )
    }
    let widget = FileLogHandler(
      label: "PodHaven/ControlledWidgetProbe",
      fileURL: WidgetInfo.recentLogFileURL,
      maxFileSizeBytes: WidgetInfo.recentLogMaxFileSizeBytes,
      targetFileSizeBytes: WidgetInfo.recentLogTargetFileSizeBytes,
      historyPolicy: .preservePreviousSession,
      writeSynchronously: { _ in false }
    )
    widget.log(
      event: LogEvent(
        level: .debug,
        message: "controlled widget ready",
        metadata: nil,
        source: "ControlledHangProbe",
        file: #fileID,
        function: #function,
        line: #line
      )
    )
    Self.log.debug("controlled session ready run=\(run)")
    let options = Sentry.Options()
    AppLauncher.configureSentryOptions(options)
    options.environment = "diagnostics-issue-644"
    options.sendDefaultPii = false
    options.enableAutoSessionTracking = false
    options.enableMetricKit = false
    let initialScope = options.initialScope
    let run = run
    options.initialScope = { scope in
      let scope = initialScope(scope)
      scope.setTag(value: run, key: "diagnostic-run")
      scope.setUser(nil)
      return scope
    }
    SentrySDK.start(options: options)
  }

  var body: some Scene {
    WindowGroup {
      Text("Controlled recovered-hang diagnostics")
        .onAppear {
          DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            Container.shared.navigation().currentTab = .settings
            Container.shared.podcastDetailPerformanceDiagnostics()
              .measure(.filterRefresh, episodeCount: 12) {}
            DispatchQueue.global()
              .async {
                true
                  .store(
                    to: ProbeStore(delay: 30) {
                      DispatchQueue.main.async {
                        true
                          .store(
                            to: ProbeStore(delay: 4) {
                              Self.log.debug("controlled hang starting")
                            },
                            forKey: "controlled-foreground"
                          )
                        Self.log.debug("controlled hang recovered")
                      }
                    },
                    forKey: "controlled-background"
                  )
              }
          }
        }
    }
  }
}
