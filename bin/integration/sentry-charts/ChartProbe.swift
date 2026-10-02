// Copyright Justin Bishop, 2026

import Charts
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
  @State private var completion = ProbeCompletion()
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
    if phase != "crash" {
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
    if phase == "churn" { return }
    let options = Sentry.Options()
    AppLauncher.configureSentryOptions(options)
    options.environment = "diagnostics-issue-724"
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
      VStack {
        Text("Controlled competing chart diagnostics")
        ForEach(0..<4) { index in
          ProbeRing(
            input: ChartProgressInput(
              source: .download,
              total: 1,
              values: [Double(step + index) / (step.isMultiple(of: 3) ? 1_000_000_000 : 1000)],
              sectorKeys: [1],
              innerRadiusRatio: 0.4,
              angularInset: 2,
              numerator: Double(step + index),
              denominator: step.isMultiple(of: 3) ? 1_000_000_000 : 1000
            ),
            width: index.isMultiple(of: 2) ? 12 : 28,
            key: "download-\(index)",
            step: step,
            completion: completion
          )
        }
        ForEach(0..<2) { index in
          ProbeRing(
            input: ChartProgressInput(
              source: .playback,
              total: 1,
              values: [Double(step / 20) / 1_000_000],
              sectorKeys: [1],
              innerRadiusRatio: 0.4,
              angularInset: 2,
              numerator: Double(step / 20),
              denominator: 1_000_000
            ),
            width: index == 0 ? 12 : 28,
            key: "playback-\(index)",
            step: step,
            completion: completion
          )
        }
        ProbeRing(
          input: ChartProgressInput(
            source: .opml,
            total: 3,
            values: step.isMultiple(of: 2) ? [0, 1, 0.000001] : [1, 1],
            sectorKeys: step.isMultiple(of: 2) ? [1, 2, 3] : [1, 2],
            innerRadiusRatio: 0.5,
            angularInset: 2,
            waitingCount: 1
          ),
          width: step.isMultiple(of: 2) ? 12 : 28,
          key: "opml",
          step: step,
          completion: completion
        )
        if step < 120 {
          CircularProgressView(colorAmounts: [.blue: 0.25], source: .download)
            .frame(width: 12, height: 12)
        }
      }
      .task {
        guard environment["PODHAVEN_CHART_PHASE"] == "crash" else { return }
        for index in 1...240 {
          do { try await Container.shared.sleeper().sleep(for: .milliseconds(16)) } catch { return }
          withAnimation(.linear(duration: 0.01)) { step = index }
        }
      }
    }
  }
}

@MainActor private final class ProbeCompletion {
  private var finalRings: Set<String> = []

  func reached(_ key: String, step: Int) {
    guard step == 240 else { return }
    finalRings.insert(key)
    guard finalRings.count == 7 else { return }
    // The boundary has stored every final input before this controlled trap.
    SentrySDK.configureScope { scope in
      scope.setTag(value: "all-final-states", key: "chart-probe-checkpoint")
    }
    SentrySDK.crash()
  }
}

private struct ProbeRing: View {
  let input: ChartProgressInput
  let width: Double
  let key: String
  let step: Int
  let completion: ProbeCompletion

  var body: some View {
    ChartDiagnosticBoundary(input: input) {
      ProbeSectors(input: input, key: key, step: step, completion: completion)
    }
    .frame(width: width, height: width)
  }
}

private struct ProbeSectors: View {
  let input: ChartProgressInput
  let key: String
  let step: Int
  let completion: ProbeCompletion

  var body: some View {
    let angularInset: CGFloat?
    if let inset = input.angularInset { angularInset = CGFloat(inset) } else { angularInset = nil }
    completion.reached(key, step: step)
    return Chart {
      ForEach(input.values.indices, id: \.self) { index in
        SectorMark(
          angle: .value("Value", input.values[index]),
          innerRadius: .ratio(input.innerRadiusRatio),
          angularInset: angularInset
        )
        .foregroundStyle(Color.blue.gradient)
      }
      if input.total > input.values.reduce(0, +) {
        SectorMark(angle: .value("Value", input.total - input.values.reduce(0, +)))
          .foregroundStyle(.opacity(0))
      }
    }
  }
}
