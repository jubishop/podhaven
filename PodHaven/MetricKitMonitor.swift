// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Logging
import MetricKit
import Sentry

extension Container {
  var metricKitExitCapture: Factory<@Sendable (Sentry.Event) -> Void> {
    Factory(self) { { event in SentrySDK.capture(event: event) } }
  }
}

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
  // so neither contributes. Drives the escalation, the message, and the Sentry
  // fingerprint, so recurrences of one failure mode share one Sentry issue
  // whatever their counts.
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

  // MetricKit delivers on a background queue. A payload can describe an earlier
  // process, so its reporting period must remain separate from the upload session.

  func didReceive(_ payloads: [MXMetricPayload]) {
    for payload in payloads {
      receive(payload)
    }
  }

  func receive(_ payload: any MetricKitMetricReporting) {
    if let counts = payload.foregroundExitCounts {
      emitExitMetric(
        counts.directive,
        abnormalReasons: counts.nonzeroAbnormalReasons,
        period: payload.reportingPeriod,
        scope: "foreground"
      )
    }
    if let counts = payload.backgroundExitCounts {
      emitExitMetric(
        Self.exitMetricDirective(for: counts),
        abnormalReasons: counts.nonzeroAbnormalReasons,
        period: payload.reportingPeriod,
        scope: "background"
      )
    }
  }

  func didReceive(_ payloads: [MXDiagnosticPayload]) {
    for payload in payloads {
      receive(payload)
    }
  }

  func receive(_ payload: any MetricKitDiagnosticReporting) {
    var eligible = 0
    for crash in payload.crashReports {
      emit(Self.diagnosticDirective(category: .crash, json: crash.jsonRepresentation()))
      guard let termination = MetricKitCrashTermination(crash) else {
        Self.log.debug(
          """
          MetricKit crash diagnostic left to the in-process crash reporter: \
          signal=\(crash.signal?.stringValue ?? "none"), \
          exceptionType=\(crash.exceptionType?.stringValue ?? "none")
          """
        )
        continue
      }
      eligible += 1
      guard eligible <= MetricKitCrashReport.maximumCapturesPerPayload else { continue }
      forward(crash, termination: termination, from: payload)
    }
    if eligible > MetricKitCrashReport.maximumCapturesPerPayload {
      Self.log.warning(
        """
        Skipped \(eligible - MetricKitCrashReport.maximumCapturesPerPayload) eligible \
        MetricKit crash diagnostics beyond the per-payload capture limit
        """
      )
    }
    for diagnostic in payload.otherDiagnostics {
      emit(Self.diagnosticDirective(category: diagnostic.category, json: diagnostic.json))
    }
  }

  // MARK: - Forwarding

  private func forward(
    _ crash: any MetricKitCrashReporting,
    termination: MetricKitCrashTermination,
    from payload: any MetricKitDiagnosticReporting
  ) {
    let launchTimeline = Container.shared.launchTimeline()
      .crashContext(pid: crash.crashMetadata.pid, endingBy: payload.timeStampEnd)
    let report: MetricKitCrashReport
    do {
      report = try MetricKitCrashReport(
        crash,
        termination: termination,
        begin: payload.timeStampBegin,
        end: payload.timeStampEnd,
        launchTimeline: launchTimeline
      )
    } catch {
      Self.log.caughtError(
        "Could not convert a MetricKit \(termination.rawValue) crash diagnostic for Sentry",
        error
      )
      return
    }
    Container.shared.metricKitCrashCapture()(report.event, report.attachments)
    Self.log.info(
      """
      Forwarded MetricKit \(termination.rawValue) crash diagnostic to Sentry: \
      frames=\(report.frameCount), attachment=\(report.attachmentStatus), \
      launchTimeline=\(launchTimeline["attribution"] ?? "missing")
      """
    )
  }

  private func emit(_ directive: MetricKitLogDirective) {
    Self.log.log(level: directive.level, "\(directive.message)", metadata: directive.metadata)
  }

  // Sentry groups by in-app stack before message, and every exit summary shares
  // this call site. Abnormal summaries therefore log below CrashReportHandler's
  // threshold and send their own event, fingerprinted by scope and reasons.
  private func emitExitMetric(
    _ directive: MetricKitLogDirective,
    abnormalReasons: [String],
    period: MetricKitReportingPeriod,
    scope: String
  ) {
    var metadata = directive.metadata.merging(period.metadata) { _, new in new }
    metadata["metricKit.scope"] = .string(scope)
    Self.log.log(level: directive.level, "\(directive.message)", metadata: metadata)
    guard !abnormalReasons.isEmpty else { return }

    let event = Sentry.Event(level: .error)
    event.message = SentryMessage(formatted: directive.message)
    event.fingerprint = ["metrickit-exit", scope] + abnormalReasons
    event.tags = ["metrickit-exit": scope]
    event.context = ["metrickit_exit": metadata.mapValues(\.description)]
    Container.shared.metricKitExitCapture()(event)
  }

  // MARK: - Decision

  // A background exit that signals an app defect escalates to .error; a routine
  // payload — graceful exits and iOS memory-pressure jettisons — stays .info.
  // Per-reason counts ride in metadata, so the message names only the reasons.
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
      level: .error,
      message: """
        MetricKit background-exit metrics — abnormal: \
        \(abnormalReasons.joined(separator: ", "))
        """,
      metadata: metadata
    )
  }

  // The raw jsonRepresentation() rides verbatim in metadata so the call-stack
  // tree (binaryUUID + offset per frame) stays machine-parseable for offline
  // symbolication; .notice keeps the entry out of Sentry Logs. Sentry's native
  // MetricKit integration files hang, CPU, and disk-write issues, but skips
  // crashes, so receive(_:) forwards eligible crash diagnostics itself.
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
