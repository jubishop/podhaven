// Copyright Justin Bishop, 2026

import Foundation
import Logging
import MetricKit

// Counts lifted out of MXBackgroundExitData so the forwarding decision can be
// exercised in tests — MXMetricPayload and friends have no public initializer.
struct BackgroundExitCounts {
  let normalAppExit: Int
  let memoryResourceLimit: Int
  let cpuResourceLimit: Int
  let memoryPressure: Int
  let badAccess: Int
  let abnormal: Int
  let illegalInstruction: Int
  let appWatchdog: Int
  let suspendedWithLockedFile: Int
  let backgroundTaskAssertionTimeout: Int

  init(
    normalAppExit: Int = 0,
    memoryResourceLimit: Int = 0,
    cpuResourceLimit: Int = 0,
    memoryPressure: Int = 0,
    badAccess: Int = 0,
    abnormal: Int = 0,
    illegalInstruction: Int = 0,
    appWatchdog: Int = 0,
    suspendedWithLockedFile: Int = 0,
    backgroundTaskAssertionTimeout: Int = 0
  ) {
    self.normalAppExit = normalAppExit
    self.memoryResourceLimit = memoryResourceLimit
    self.cpuResourceLimit = cpuResourceLimit
    self.memoryPressure = memoryPressure
    self.badAccess = badAccess
    self.abnormal = abnormal
    self.illegalInstruction = illegalInstruction
    self.appWatchdog = appWatchdog
    self.suspendedWithLockedFile = suspendedWithLockedFile
    self.backgroundTaskAssertionTimeout = backgroundTaskAssertionTimeout
  }

  init(_ data: MXBackgroundExitData) {
    self.init(
      normalAppExit: data.cumulativeNormalAppExitCount,
      memoryResourceLimit: data.cumulativeMemoryResourceLimitExitCount,
      cpuResourceLimit: data.cumulativeCPUResourceLimitExitCount,
      memoryPressure: data.cumulativeMemoryPressureExitCount,
      badAccess: data.cumulativeBadAccessExitCount,
      abnormal: data.cumulativeAbnormalExitCount,
      illegalInstruction: data.cumulativeIllegalInstructionExitCount,
      appWatchdog: data.cumulativeAppWatchdogExitCount,
      suspendedWithLockedFile: data.cumulativeSuspendedWithLockedFileExitCount,
      backgroundTaskAssertionTimeout: data.cumulativeBackgroundTaskAssertionTimeoutExitCount
    )
  }

  // Names of the background-exit reasons that signal an app defect and have a
  // nonzero count in this payload, in a stable order. A graceful exit and an
  // iOS memory-pressure jettison of a suspended app are both routine reclaim,
  // so neither contributes. Drives the .critical escalation and feeds the
  // Sentry-grouping message — keeping the names off counts means recurrences
  // of the same failure mode collapse into one Sentry issue.
  var nonzeroAbnormalReasons: [String] {
    var reasons: [String] = []
    if memoryResourceLimit > 0 { reasons.append("memoryResourceLimit") }
    if cpuResourceLimit > 0 { reasons.append("cpuResourceLimit") }
    if badAccess > 0 { reasons.append("badAccess") }
    if abnormal > 0 { reasons.append("abnormal") }
    if illegalInstruction > 0 { reasons.append("illegalInstruction") }
    if appWatchdog > 0 { reasons.append("appWatchdog") }
    if suspendedWithLockedFile > 0 { reasons.append("suspendedWithLockedFile") }
    if backgroundTaskAssertionTimeout > 0 { reasons.append("backgroundTaskAssertionTimeout") }
    return reasons
  }
}

enum MetricKitDiagnosticCategory: String {
  case crash
  case hang
  case cpuException
  case diskWriteException
  case appLaunch
}

struct MetricKitLogDirective {
  let level: Logging.Logger.Level
  let message: String
  let metadata: Logging.Logger.Metadata
}

final class MetricKitMonitor: NSObject, MXMetricManagerSubscriber, Sendable {
  private static let log = Log.as("MetricKit")

  // MARK: - MXMetricManagerSubscriber

  // MetricKit invokes both callbacks on a background queue: metrics roughly
  // once per 24 h, diagnostics on the launch after the event.

  func didReceive(_ payloads: [MXMetricPayload]) {
    for payload in payloads {
      guard let backgroundExit = payload.applicationExitMetrics?.backgroundExitData else {
        continue
      }
      emit(Self.exitMetricDirective(for: BackgroundExitCounts(backgroundExit)))
    }
  }

  func didReceive(_ payloads: [MXDiagnosticPayload]) {
    for payload in payloads {
      forward(payload.crashDiagnostics, as: .crash)
      forward(payload.hangDiagnostics, as: .hang)
      forward(payload.cpuExceptionDiagnostics, as: .cpuException)
      forward(payload.diskWriteExceptionDiagnostics, as: .diskWriteException)
      forward(payload.appLaunchDiagnostics, as: .appLaunch)
    }
  }

  // MARK: - Forwarding

  private func forward<Diagnostic: MXDiagnostic>(
    _ diagnostics: [Diagnostic]?,
    as category: MetricKitDiagnosticCategory
  ) {
    guard let diagnostics else { return }
    for diagnostic in diagnostics {
      emit(Self.diagnosticDirective(category: category, json: diagnostic.jsonRepresentation()))
    }
  }

  private func emit(_ directive: MetricKitLogDirective) {
    Self.log.log(level: directive.level, "\(directive.message)", metadata: directive.metadata)
  }

  // MARK: - Decision

  // A background exit that signals an app defect escalates to .critical so
  // CrashReportHandler files a Sentry issue; a routine payload — graceful exits
  // and iOS memory-pressure jettisons — stays .info. Per-reason counts ride in
  // metadata so the .critical message stays identical across recurrences and
  // Sentry's message-based grouping collapses repeats of the same failure mode.
  static func exitMetricDirective(for counts: BackgroundExitCounts) -> MetricKitLogDirective {
    let metadata: Logging.Logger.Metadata = [
      "normalAppExit": .string("\(counts.normalAppExit)"),
      "memoryResourceLimit": .string("\(counts.memoryResourceLimit)"),
      "cpuResourceLimit": .string("\(counts.cpuResourceLimit)"),
      "memoryPressure": .string("\(counts.memoryPressure)"),
      "badAccess": .string("\(counts.badAccess)"),
      "abnormal": .string("\(counts.abnormal)"),
      "illegalInstruction": .string("\(counts.illegalInstruction)"),
      "appWatchdog": .string("\(counts.appWatchdog)"),
      "suspendedWithLockedFile": .string("\(counts.suspendedWithLockedFile)"),
      "backgroundTaskAssertionTimeout": .string("\(counts.backgroundTaskAssertionTimeout)"),
    ]
    let abnormalReasons = counts.nonzeroAbnormalReasons
    if abnormalReasons.isEmpty {
      return MetricKitLogDirective(
        level: .info,
        message: "MetricKit background-exit metrics — routine",
        metadata: metadata
      )
    }
    return MetricKitLogDirective(
      level: .critical,
      message:
        "MetricKit background-exit metrics — abnormal: \(abnormalReasons.joined(separator: ", "))",
      metadata: metadata
    )
  }

  // The raw jsonRepresentation() rides verbatim in metadata so the call-stack
  // tree (binaryUUID + offset per frame) stays machine-parseable for offline
  // symbolication; .notice keeps the entry out of Sentry Logs, since the native
  // MetricKit integration already files the symbolicated issue.
  static func diagnosticDirective(
    category: MetricKitDiagnosticCategory,
    json: Data
  ) -> MetricKitLogDirective {
    MetricKitLogDirective(
      level: .notice,
      message: "MetricKit \(category.rawValue) diagnostic received",
      metadata: ["metricKitDiagnostic": .string(String(decoding: json, as: UTF8.self))]
    )
  }
}
