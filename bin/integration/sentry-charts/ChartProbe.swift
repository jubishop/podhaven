// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Logging
import OrderedCollections
import Sentry
import SwiftUI

private final class ProbeFileManager: FileManager, @unchecked Sendable {
  override func containerURL(forSecurityApplicationGroupIdentifier groupIdentifier: String) -> URL?
  {
    URL.documentsDirectory.appendingPathComponent("widget", isDirectory: true)
  }
}

@main
struct ChartProbe: App {
  @State private var step = 0
  private let environment = ProcessInfo.processInfo.environment

  init() {
    Container.shared.fileManager.register { ProbeFileManager() }
    Container.shared.siriCatalogFile.register {
      SiriCatalogFile(url: URL.documentsDirectory.appendingPathComponent("siri-media.json"))
    }
    AppInfo.initializeEnvironment()
    let run = environment["PODHAVEN_CHART_RUN"] ?? UUID().uuidString
    let phase = environment["PODHAVEN_CHART_PHASE"] ?? "crash"
    let log = FileLogHandler(
      label: "PodHaven/ChartProbe",
      fileURL: AppInfo.recentLogFileURL,
      maxFileSizeBytes: AppInfo.recentLogMaxFileSizeBytes,
      targetFileSizeBytes: AppInfo.recentLogTargetFileSizeBytes,
      historyPolicy: .preservePreviousSession,
      writeSynchronously: { _ in true }
    )
    if phase == "relaunch" {
      let instance = ChartProgressInstance()
      for index in 0..<500 {
        log.log(
          event: LogEvent(
            level: .debug,
            message: "controlled launch churn \(index)",
            metadata: nil,
            source: "ChartProbe",
            file: #fileID,
            function: #function,
            line: UInt(index)
          )
        )
        instance.record(
          ChartProgressInput(
            source: .download,
            total: 1,
            values: [Double(index) / 500],
            sectorKeys: [1],
            innerRadiusRatio: 0.4,
            angularInset: 2,
            numerator: Double(index),
            denominator: 500
          ),
          size: CGSize(width: 12, height: 12),
          scene: .active,
          phase: .render
        )
      }
    }
    let options = Sentry.Options()
    AppLauncher.configureSentryOptions(options)
    options.environment = "diagnostics-issue-720"
    options.sendDefaultPii = false
    options.enableAutoSessionTracking = false
    options.enableMetricKit = false
    options.enableAppHangTracking = false
    let initialScope = options.initialScope
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
      let progress = [0.0, 0.000001, 0.25, 0.5, 1.0, 1.1, 0.01, 0.75][step]
      let size = step.isMultiple(of: 2) ? 12.0 : 28.0
      VStack {
        Text("Controlled chart diagnostics")
        CircularProgressView(
          colorAmounts: [.blue: progress],
          innerRadiusRatio: 0.4,
          source: .playback,
          numerator: progress * 100,
          denominator: 100
        )
        .frame(width: size, height: size)
        CircularProgressView(
          colorAmounts: [.blue: min(progress, 1)],
          innerRadiusRatio: 0.4,
          source: .download,
          numerator: min(progress, 1) * 100,
          denominator: 100
        )
        .frame(width: size, height: size)
        CircularProgressView(
          totalAmount: 3,
          colorAmounts: step.isMultiple(of: 2)
            ? [.green: 0, .blue: 1, .red: 1] : [.green: 1, .blue: 1],
          source: .opml,
          waitingCount: 1
        )
        .frame(width: size, height: size)
      }
      .onAppear {
        guard environment["PODHAVEN_CHART_PHASE"] == "crash" else { return }
        for index in 1..<8 {
          DispatchQueue.main.asyncAfter(deadline: .now() + Double(index)) {
            withAnimation(.linear(duration: 0.1)) { step = index }
          }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
          SentrySDK.crash()
        }
      }
    }
  }
}
