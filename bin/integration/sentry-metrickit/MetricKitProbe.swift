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

private struct ProbeCrash: MetricKitCrashReporting {
  let applicationVersion: String
  let crashMetadata: MetricKitCrashMetadata
  let exceptionType: NSNumber?
  let exceptionCode: NSNumber?
  let signal: NSNumber?
  let terminationReason: String?
  let objectiveCException: MetricKitObjectiveCException? = nil
  let callStackTreeJSON: Data
  let raw: Data

  func jsonRepresentation() -> Data { raw }
}

private struct ProbePayload: MetricKitDiagnosticReporting {
  let timeStampBegin: Date
  let timeStampEnd: Date
  let crashReports: [any MetricKitCrashReporting]
  let otherDiagnostics: [MetricKitDiagnosticRecord] = []
}

@main
struct MetricKitProbe: App {
  nonisolated private static let log = Log.as("ControlledMetricKitProbe")
  private let run = ProcessInfo.processInfo.environment["PODHAVEN_METRICKIT_RUN"] ?? "missing"
  private let phase = ProcessInfo.processInfo.environment["PODHAVEN_METRICKIT_PHASE"] ?? "missing"

  init() {
    Container.shared.fileManager.register { ProbeFileManager() }
    Container.shared.siriCatalogFile.register {
      SiriCatalogFile(url: URL.documentsDirectory.appendingPathComponent("siri-media.json"))
    }
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
    let timeline = Container.shared.launchTimeline()
    timeline.record(.loggingStarted)
    Self.log.debug("controlled session ready run=\(run) phase=\(phase)")
    timeline.record(.logsOpened)
    let options = Sentry.Options()
    AppLauncher.configureSentryOptions(options)
    options.environment = "diagnostics-issue-740"
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
    timeline.record(.sentryStarted)
    guard phase == "launch" else { return }
    // The smoke helper waits for this flushed record, then kills this launch with SIGKILL.
    Self.log.debug("controlled launch timeline recorded run=\(run) pid=\(getpid())")
    FileLogHandler.flush()
  }

  var body: some Scene {
    WindowGroup {
      Text("Controlled MetricKit crash forwarding")
        .onAppear {
          guard phase == "deliver" else { return }
          DispatchQueue.main.asyncAfter(deadline: .now() + 3) { Self.deliver() }
        }
    }
  }

  private static func deliver() {
    let environment = ProcessInfo.processInfo.environment
    guard let text = environment["PODHAVEN_METRICKIT_DIAGNOSTIC"] else {
      fatalError("Missing controlled MetricKit diagnostic")
    }
    let raw = Data(text.utf8)
    let tree: Data
    let object: [String: Any]
    do {
      guard let decoded = try JSONSerialization.jsonObject(with: raw) as? [String: Any],
        let callStackTree = decoded["callStackTree"]
      else { fatalError("Controlled MetricKit diagnostic has no call stack tree") }
      object = decoded
      tree = try JSONSerialization.data(withJSONObject: callStackTree)
    } catch {
      fatalError("Unable to read controlled MetricKit diagnostic: \(error)")
    }
    guard let meta = object["diagnosticMetaData"] as? [String: Any],
      let version = meta["appVersion"] as? String,
      let build = meta["appBuildVersion"] as? String,
      let osVersion = meta["osVersion"] as? String,
      let architecture = meta["platformArchitecture"] as? String,
      let deviceType = meta["deviceType"] as? String,
      let bundleIdentifier = meta["bundleIdentifier"] as? String,
      let pid = meta["pid"] as? NSNumber
    else { fatalError("Controlled MetricKit diagnostic has incomplete metadata") }
    let crash = ProbeCrash(
      applicationVersion: version,
      crashMetadata: MetricKitCrashMetadata(
        applicationBuildVersion: build,
        osVersion: osVersion,
        platformArchitecture: architecture,
        deviceType: deviceType,
        bundleIdentifier: bundleIdentifier,
        pid: pid.int32Value
      ),
      exceptionType: meta["exceptionType"] as? NSNumber,
      exceptionCode: meta["exceptionCode"] as? NSNumber,
      signal: meta["signal"] as? NSNumber,
      terminationReason: meta["terminationReason"] as? String,
      callStackTreeJSON: tree,
      raw: raw
    )
    let end = Date()
    MetricKitMonitor()
      .receive(
        ProbePayload(
          timeStampBegin: end.addingTimeInterval(-60),
          timeStampEnd: end,
          crashReports: [crash]
        )
      )
    log.debug("controlled MetricKit delivery complete")
  }
}
