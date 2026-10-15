// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import MetricKit
import Sentry

extension Container {
  var metricKitCrashCapture: Factory<@Sendable (Sentry.Event, [Sentry.Attachment]) -> Void> {
    Factory(self) {
      { event, attachments in
        SentrySDK.capture(event: event) { scope in
          for attachment in attachments {
            scope.addAttachment(attachment)
          }
        }
      }
    }
  }
}

struct MetricKitCrashMetadata {
  let applicationBuildVersion: String
  let osVersion: String
  let platformArchitecture: String
  let deviceType: String
  let bundleIdentifier: String
}

struct MetricKitObjectiveCException {
  let name: String
  let className: String
  let type: String
}

protocol MetricKitCrashReporting {
  var applicationVersion: String { get }
  var crashMetadata: MetricKitCrashMetadata { get }
  var exceptionType: NSNumber? { get }
  var exceptionCode: NSNumber? { get }
  var signal: NSNumber? { get }
  var terminationReason: String? { get }
  var objectiveCException: MetricKitObjectiveCException? { get }
  var callStackTreeJSON: Data { get }
  func jsonRepresentation() -> Data
}

struct MetricKitDiagnosticRecord {
  let category: MetricKitDiagnosticCategory
  let json: Data
}

protocol MetricKitDiagnosticReporting {
  var timeStampBegin: Date { get }
  var timeStampEnd: Date { get }
  var crashReports: [any MetricKitCrashReporting] { get }
  var otherDiagnostics: [MetricKitDiagnosticRecord] { get }
}

extension MXCrashDiagnostic: MetricKitCrashReporting {
  var crashMetadata: MetricKitCrashMetadata {
    MetricKitCrashMetadata(
      applicationBuildVersion: metaData.applicationBuildVersion,
      osVersion: metaData.osVersion,
      platformArchitecture: metaData.platformArchitecture,
      deviceType: metaData.deviceType,
      bundleIdentifier: metaData.bundleIdentifier
    )
  }

  var objectiveCException: MetricKitObjectiveCException? {
    guard let exceptionReason else { return nil }
    return MetricKitObjectiveCException(
      name: exceptionReason.exceptionName,
      className: exceptionReason.className,
      type: exceptionReason.exceptionType
    )
  }

  var callStackTreeJSON: Data { callStackTree.jsonRepresentation() }
}

extension MXDiagnosticPayload: MetricKitDiagnosticReporting {
  var crashReports: [any MetricKitCrashReporting] { crashDiagnostics ?? [] }

  var otherDiagnostics: [MetricKitDiagnosticRecord] {
    let groups: [(MetricKitDiagnosticCategory, [MXDiagnostic]?)] = [
      (.hang, hangDiagnostics),
      (.cpuException, cpuExceptionDiagnostics),
      (.diskWriteException, diskWriteExceptionDiagnostics),
      (.appLaunch, appLaunchDiagnostics),
    ]
    return groups.flatMap { category, diagnostics in
      (diagnostics ?? [])
        .map { MetricKitDiagnosticRecord(category: category, json: $0.jsonRepresentation()) }
    }
  }
}

enum MetricKitCrashTermination: String {
  case watchdog
  case resourceLimit = "resource_limit"
  case guardViolation = "guard"
  case killed = "sigkill"

  // Sentry's in-process reporter catches the catchable fatal signals and the
  // Mach exceptions behind them, but never SIGKILL or the kernel's EXC_RESOURCE
  // and EXC_GUARD kills. Only those are eligible, so its reports aren't duplicated.
  init?(_ crash: any MetricKitCrashReporting) {
    let reason = crash.terminationReason?.lowercased() ?? ""
    let exceptionType = crash.exceptionType?.int32Value
    if ["watchdog", "8badf00d", "2343432205"].contains(where: { reason.contains($0) }) {
      self = .watchdog
    } else if exceptionType == EXC_RESOURCE {
      self = .resourceLimit
    } else if exceptionType == EXC_GUARD {
      self = .guardViolation
    } else if crash.signal?.int32Value == SIGKILL {
      self = .killed
    } else {
      return nil
    }
  }

  var title: String {
    switch self {
    case .watchdog: "Watchdog termination"
    case .resourceLimit: "Resource-limit termination"
    case .guardViolation: "Guard termination"
    case .killed: "SIGKILL termination"
    }
  }
}

struct MetricKitCrashReport {
  static let maximumCapturesPerPayload = 5
  static let maximumAttachmentBytes = 256 * 1024
  static let maximumThreads = 32
  static let maximumFramesPerThread = 128
  static let maximumReasonLength = 512

  private static let mechanism = "MXCrashDiagnostic"

  private struct CallStackTree: Decodable {
    let callStacks: [CallStack]
  }

  private struct CallStack: Decodable {
    let threadAttributed: Bool?
    let callStackRootFrames: [CallStackFrame]
  }

  private struct CallStackFrame: Decodable {
    let binaryUUID: String?
    let binaryName: String?
    let offsetIntoBinaryTextSegment: UInt64?
    let address: UInt64?
    let sampleCount: Int?
    let subFrames: [CallStackFrame]?
  }

  private enum ConversionError: Error {
    case noFrames
  }

  let event: Sentry.Event
  let attachments: [Sentry.Attachment]
  let frameCount: Int
  let attachmentStatus: String

  init(
    _ crash: any MetricKitCrashReporting,
    termination: MetricKitCrashTermination,
    begin: Date,
    end: Date
  ) throws {
    let tree = try JSONDecoder().decode(CallStackTree.self, from: crash.callStackTreeJSON)
    let executable = Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String
    var threads: [SentryThread] = []
    var images: [DebugMeta] = []
    var imageIDs: Set<String> = []
    var frameCount = 0
    var truncatedThreads = 0
    for (index, callStack) in tree.callStacks.enumerated()
    where index < Self.maximumThreads || callStack.threadAttributed == true {
      let path = Self.mostSampledPath(callStack.callStackRootFrames)
      let kept = path.suffix(Self.maximumFramesPerThread)
      if kept.count < path.count { truncatedThreads += 1 }
      var frames: [Frame] = []
      for callStackFrame in kept {
        let frame = Frame()
        frame.package = callStackFrame.binaryName
        frame.inApp = NSNumber(
          value: callStackFrame.binaryName == nil || callStackFrame.binaryName == executable
        )
        if let address = callStackFrame.address {
          frame.instructionAddress = Self.hex(address)
          if let offset = callStackFrame.offsetIntoBinaryTextSegment, offset < address {
            let imageAddress = Self.hex(address - offset)
            frame.imageAddress = imageAddress
            if let uuid = callStackFrame.binaryUUID, imageIDs.insert(uuid).inserted {
              let image = DebugMeta()
              image.type = "macho"
              image.debugID = uuid
              image.codeFile = callStackFrame.binaryName
              image.imageAddress = imageAddress
              images.append(image)
            }
          }
        }
        frames.append(frame)
      }
      frameCount += frames.count
      let thread = SentryThread(threadId: NSNumber(value: index))
      thread.stacktrace = SentryStacktrace(frames: frames, registers: [:])
      thread.crashed = NSNumber(value: callStack.threadAttributed == true)
      threads.append(thread)
    }
    guard frameCount > 0,
      let exceptionThread = threads.first(where: { $0.crashed?.boolValue == true })
        ?? threads.first
    else { throw ConversionError.noFrames }

    let mechanism = Mechanism(type: Self.mechanism)
    mechanism.handled = false
    mechanism.synthetic = true
    var details: [String] = []
    if let exceptionType = crash.exceptionType {
      let name =
        switch exceptionType.int32Value {
        case EXC_CRASH: "EXC_CRASH"
        case EXC_RESOURCE: "EXC_RESOURCE"
        case EXC_GUARD: "EXC_GUARD"
        default: "Mach exception \(exceptionType)"
        }
      details.append(name)
    }
    if let signal = crash.signal {
      var signalMeta: [String: Any] = ["number": signal]
      if signal.int32Value == SIGKILL {
        signalMeta["name"] = "SIGKILL"
        details.append("SIGKILL")
      } else {
        details.append("signal \(signal)")
      }
      let meta = MechanismContext()
      meta.signal = signalMeta
      mechanism.meta = meta
    }
    let summary =
      details.isEmpty
      ? termination.title : "\(termination.title) (\(details.joined(separator: ", ")))"
    let exception = Exception(value: summary, type: Self.mechanism)
    exception.mechanism = mechanism
    exception.stacktrace = exceptionThread.stacktrace
    exception.threadId = exceptionThread.threadId

    let metadata = crash.crashMetadata
    let version = String(crash.applicationVersion.prefix(64))
    let build = String(metadata.applicationBuildVersion.prefix(64))
    let raw = crash.jsonRepresentation()
    if crash.objectiveCException != nil {
      attachments = []
      attachmentStatus = "omitted_exception_message"
    } else if raw.count > Self.maximumAttachmentBytes {
      attachments = []
      attachmentStatus = "omitted_over_limit"
    } else {
      attachments = [
        Sentry.Attachment(
          data: raw,
          filename: "metrickit-crash-diagnostic.json",
          contentType: "application/json"
        )
      ]
      attachmentStatus = "included"
    }

    var context: [String: Any] = [
      "termination": termination.rawValue,
      "attribution": "diagnostic_metadata",
      "observation": "delivery_launch",
      "deliverySessionID": FileLogHandler.sessionID,
      "appVersion": version,
      "appBuild": build,
      "osVersion": String(metadata.osVersion.prefix(64)),
      "platformArchitecture": String(metadata.platformArchitecture.prefix(64)),
      "deviceType": String(metadata.deviceType.prefix(64)),
      "bundleIdentifier": String(metadata.bundleIdentifier.prefix(64)),
      "periodStart": begin.ISO8601Format(),
      "periodEnd": end.ISO8601Format(),
      "threads": threads.count,
      "omittedThreads": tree.callStacks.count - threads.count,
      "frames": frameCount,
      "truncatedThreads": truncatedThreads,
      "rawPayloadBytes": raw.count,
      "rawPayloadAttachment": attachmentStatus,
    ]
    if let exceptionType = crash.exceptionType { context["exceptionType"] = exceptionType }
    if let exceptionCode = crash.exceptionCode { context["exceptionCode"] = exceptionCode }
    if let signal = crash.signal { context["signal"] = signal }
    if let terminationReason = crash.terminationReason {
      context["terminationReason"] = String(terminationReason.prefix(Self.maximumReasonLength))
    }
    if let objectiveCException = crash.objectiveCException {
      context["objectiveCException"] = [
        "name": String(objectiveCException.name.prefix(128)),
        "className": String(objectiveCException.className.prefix(128)),
        "type": String(objectiveCException.type.prefix(128)),
      ]
    }

    let event = Sentry.Event(level: .fatal)
    event.timestamp = begin
    event.exceptions = [exception]
    event.threads = threads
    event.debugMeta = images
    event.releaseName = "\(String(metadata.bundleIdentifier.prefix(64)))@\(version)+\(build)"
    event.dist = build
    event.fingerprint = ["{{ default }}", "metrickit-crash", termination.rawValue]
    event.tags = ["metrickit-crash": termination.rawValue]
    event.context = [
      "app": ["app_version": version, "app_build": build],
      "metrickit_crash": context,
    ]
    self.event = event
    self.frameCount = frameCount
  }

  // MetricKit roots each call tree at the outermost caller and splits it where
  // samples diverge; following the most-sampled child yields Sentry's
  // caller-to-callee frame order.
  private static func mostSampledPath(_ roots: [CallStackFrame]) -> [CallStackFrame] {
    var path: [CallStackFrame] = []
    var candidates = roots
    while let next = candidates.max(by: { ($0.sampleCount ?? 0) < ($1.sampleCount ?? 0) }) {
      path.append(next)
      candidates = next.subFrames ?? []
    }
    return path
  }

  private static func hex(_ value: UInt64) -> String { "0x" + String(value, radix: 16) }
}
