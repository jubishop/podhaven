// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Logging
import Sentry
import Testing

@testable import PodHaven

@Suite("of MetricKit crash forwarding tests", .container)
struct MetricKitCrashForwardingTests {
  private struct StackFrame {
    let binary: String
    let uuid: String
    let offset: UInt64
  }

  private struct StackThread {
    var attributed = false
    let frames: [StackFrame]
  }

  private struct Crash: MetricKitCrashReporting {
    var applicationVersion = "1.4"
    var crashMetadata = MetricKitCrashMetadata(
      applicationBuildVersion: "612",
      osVersion: "iPhone OS 26.1 (23B85)",
      platformArchitecture: "arm64e",
      deviceType: "iPhone17,1",
      bundleIdentifier: "com.artisanalsoftware.PodHaven",
      pid: 4242
    )
    var exceptionType: NSNumber? = 10
    var exceptionCode: NSNumber? = 0
    var signal: NSNumber? = 9
    var terminationReason: String? = "Namespace FRONTBOARD, Code 0x8badf00d"
    var objectiveCException: MetricKitObjectiveCException?
    var callStackTreeJSON: Data
    var raw: Data?

    func jsonRepresentation() -> Data {
      if let raw { return raw }
      return Data(#"{"diagnosticMetaData":{"signal":9},"callStackTree":"#.utf8) + callStackTreeJSON
        + Data("}".utf8)
    }
  }

  private struct Payload: MetricKitDiagnosticReporting {
    var timeStampBegin = Date(timeIntervalSince1970: 1_790_000_000)
    var timeStampEnd = Date(timeIntervalSince1970: 1_790_003_600)
    var crashReports: [any MetricKitCrashReporting] = []
    var otherDiagnostics: [MetricKitDiagnosticRecord] = []
  }

  private struct Capture: Sendable {
    let event: Data
    let attachmentName: String?
    let attachmentType: String?
    let attachment: Data?
  }

  private struct Values<Value: Decodable>: Decodable {
    let values: [Value]
  }

  private struct WireFrame: Decodable, Equatable {
    let package: String?
    let instructionAddr: String?
    let imageAddr: String?
    let inApp: Bool?
  }

  private struct WireStacktrace: Decodable {
    let frames: [WireFrame]
  }

  private struct WireThread: Decodable {
    let id: Int
    let crashed: Bool?
    let stacktrace: WireStacktrace
  }

  private struct WireSignal: Decodable {
    let number: Int
    let name: String?
  }

  private struct WireMeta: Decodable {
    let signal: WireSignal?
  }

  private struct WireMechanism: Decodable {
    let type: String
    let handled: Bool?
    let synthetic: Bool?
    let meta: WireMeta?
  }

  private struct WireException: Decodable {
    let type: String?
    let value: String?
    let mechanism: WireMechanism?
    let threadId: Int?
    let stacktrace: WireStacktrace?
  }

  private struct WireImage: Decodable {
    let type: String?
    let debugId: String?
    let imageAddr: String?
    let codeFile: String?
  }

  private struct WireDebugMeta: Decodable {
    let images: [WireImage]
  }

  private struct WireAppContext: Decodable {
    let appVersion: String?
    let appBuild: String?
  }

  private struct WireObjectiveCException: Decodable {
    let name: String
    let className: String
    let type: String
  }

  private struct WireCrashContext: Decodable {
    let termination: String
    let attribution: String
    let observation: String
    let deliverySessionID: String
    let appVersion: String
    let appBuild: String
    let osVersion: String
    let platformArchitecture: String
    let deviceType: String
    let bundleIdentifier: String
    let pid: Int32
    let periodStart: String
    let periodEnd: String
    let exceptionType: Int?
    let exceptionCode: Int?
    let signal: Int?
    let terminationReason: String?
    let objectiveCException: WireObjectiveCException?
    let threads: Int
    let omittedThreads: Int
    let frames: Int
    let truncatedThreads: Int
    let rawPayloadBytes: Int
    let rawPayloadAttachment: String
  }

  private struct WireLaunchTimeline: Decodable {
    let attribution: String
    let pid: Int32
    let sessionID: String?
    let lastMilestone: String?
    let millisecondsAfterOrigin: [String: Int]?
  }

  private struct WireContexts: Decodable {
    let app: WireAppContext?
    let metrickitCrash: WireCrashContext
    let launchTimeline: WireLaunchTimeline?
  }

  private struct WireEvent: Decodable {
    let level: String
    let release: String?
    let dist: String?
    let fingerprint: [String]?
    let tags: [String: String]?
    let timestamp: Double?
    let exception: Values<WireException>
    let threads: Values<WireThread>
    let debugMeta: WireDebugMeta
    let contexts: WireContexts
  }

  private static let imageBases: [String: UInt64] = [
    "PodHaven": 0x1_0000_0000,
    "dyld": 0x1_8000_0000,
    "UIKitCore": 0x1_9000_0000,
    "libsystem_kernel.dylib": 0x1_a000_0000,
    #"Plug-In "{[\ Bundle"#: 0x1_b000_0000,
  ]

  private static let start = StackFrame(
    binary: "dyld",
    uuid: "3A1E7F20-4B6C-3D5E-8F90-A1B2C3D4E5F6",
    offset: 0x5f0c
  )
  private static let appMain = StackFrame(
    binary: "PodHaven",
    uuid: "9C2D4E6F-1A3B-3C5D-9E7F-0A1B2C3D4E5F",
    offset: 0x1a2b0
  )
  private static let applicationMain = StackFrame(
    binary: "UIKitCore",
    uuid: "5B7C9D1E-2F3A-3B4C-8D5E-6F7A8B9C0D1E",
    offset: 0x30c4c8
  )
  private static let appWork = StackFrame(
    binary: "PodHaven",
    uuid: "9C2D4E6F-1A3B-3C5D-9E7F-0A1B2C3D4E5F",
    offset: 0x8f4c0
  )
  private static let trap = StackFrame(
    binary: "libsystem_kernel.dylib",
    uuid: "7D8E9F0A-1B2C-3D4E-8F5A-6B7C8D9E0F1A",
    offset: 0x1234
  )
  private static let plugIn = StackFrame(
    binary: #"Plug-In "{[\ Bundle"#,
    uuid: "2E4F6A8B-0C1D-3E2F-9A4B-5C6D7E8F9A0B",
    offset: 0x2468
  )

  private static let mainThread = StackThread(
    attributed: true,
    frames: [start, appMain, applicationMain, appWork, trap]
  )
  private static let workerThread = StackThread(frames: [appWork, trap])

  private static func hex(_ value: UInt64) -> String { "0x" + String(value, radix: 16) }

  private static func base(_ binary: String, slide: UInt64) -> UInt64 {
    (imageBases[binary] ?? 0) + slide
  }

  private static func wireFrames(_ frames: [StackFrame]) -> [WireFrame] {
    frames.map { frame in
      WireFrame(
        package: frame.binary,
        instructionAddr: hex(base(frame.binary, slide: 0) + frame.offset),
        imageAddr: hex(base(frame.binary, slide: 0)),
        inApp: frame.binary == "PodHaven"
      )
    }
  }

  // Like MetricKit, roots each stack at the crashing frame and nests callers in subFrames.
  // Written as text because JSONSerialization recurses per level and deep stacks
  // overflow a test thread's stack.
  private static func tree(_ threads: [StackThread], slide: UInt64 = 0) -> Data {
    let stacks = threads.map { thread in
      let frames = thread.frames.reversed()
        .map { frame in
          let binary = frame.binary.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"")
          return """
            {"binaryUUID":"\(frame.uuid)","binaryName":"\(binary)",\
            "offsetIntoBinaryTextSegment":\(frame.offset),\
            "address":\(base(frame.binary, slide: slide) + frame.offset),"sampleCount":1
            """
        }
      let roots =
        frames.isEmpty
        ? ""
        : frames.joined(separator: #","subFrames":["#)
          + String(repeating: "}]", count: frames.count - 1) + "}"
      return #"{"threadAttributed":\#(thread.attributed),"callStackRootFrames":[\#(roots)]}"#
    }
    return Data(
      #"{"callStackPerThread":true,"callStacks":[\#(stacks.joined(separator: ","))]}"#.utf8
    )
  }

  private static func crash(
    threads: [StackThread] = [mainThread, workerThread],
    slide: UInt64 = 0
  ) -> Crash {
    Crash(callStackTreeJSON: tree(threads, slide: slide))
  }

  private func captures(_ payloads: [Payload]) -> [Capture] {
    let captured = ThreadSafe<[Capture]>([])
    Container.shared.metricKitCrashCapture.context(.test) {
      { event, attachments in
        #expect(attachments.count <= 1)
        let attachment = attachments.first
        let json: Data
        do {
          json = try JSONSerialization.data(withJSONObject: event.serialize())
        } catch {
          Issue.record(error)
          return
        }
        let capture = Capture(
          event: json,
          attachmentName: attachment?.filename,
          attachmentType: attachment?.contentType,
          attachment: attachment?.data
        )
        captured { $0.append(capture) }
      }
    }
    let monitor = MetricKitMonitor()
    for payload in payloads {
      monitor.receive(payload)
    }
    return captured()
  }

  private func decode(_ capture: Capture) throws -> WireEvent {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(WireEvent.self, from: capture.event)
  }

  // MARK: - Capture

  @Test("a watchdog crash diagnostic produces one Sentry capture attributed to its own build")
  func watchdogCrashIsCaptured() throws {
    let crash = Self.crash()
    let payload = Payload(crashReports: [crash])
    let (captured, logs) = LogCapture.withSink { sink in
      (captures([payload]), sink.captured().filter { $0.label == "PodHaven/MetricKit" })
    }

    #expect(captured.count == 1)
    let capture = try #require(captured.first)
    let event = try decode(capture)

    #expect(event.level == "fatal")
    #expect(event.release == "com.artisanalsoftware.PodHaven@1.4+612")
    #expect(event.dist == "612")
    #expect(
      event.release != "\(AppInfo.bundleIdentifier)@\(AppInfo.version)+\(AppInfo.buildNumber)"
    )
    #expect(event.timestamp == payload.timeStampBegin.timeIntervalSince1970)
    #expect(event.tags?["metrickit-crash"] == "watchdog")
    #expect(event.contexts.app?.appVersion == "1.4")
    #expect(event.contexts.app?.appBuild == "612")

    let exception = try #require(event.exception.values.first)
    #expect(event.exception.values.count == 1)
    #expect(exception.type == "MXCrashDiagnostic")
    #expect(exception.value?.contains("EXC_CRASH") == true)
    #expect(exception.value?.contains("SIGKILL") == true)
    #expect(exception.mechanism?.type == "MXCrashDiagnostic")
    #expect(exception.mechanism?.handled == false)
    #expect(exception.mechanism?.synthetic == true)
    #expect(exception.mechanism?.meta?.signal?.number == 9)
    #expect(exception.mechanism?.meta?.signal?.name == "SIGKILL")

    #expect(event.threads.values.map(\.id) == [0, 1])
    #expect(event.threads.values.map(\.crashed) == [true, false])
    #expect(exception.threadId == 0)
    let expectedFrames = Self.wireFrames(Self.mainThread.frames)
    #expect(exception.stacktrace?.frames == expectedFrames)
    #expect(event.threads.values.first?.stacktrace.frames == expectedFrames)

    let images = event.debugMeta.images
    #expect(images.count == 4)
    #expect(Set(images.compactMap(\.debugId)) == Set(Self.mainThread.frames.map(\.uuid)))
    #expect(images.allSatisfy { $0.type == "macho" })
    let app = try #require(images.first { $0.codeFile == "PodHaven" })
    #expect(app.debugId == Self.appMain.uuid)
    #expect(app.imageAddr == Self.hex(Self.base("PodHaven", slide: 0)))

    let context = event.contexts.metrickitCrash
    #expect(context.termination == "watchdog")
    #expect(context.attribution == "diagnostic_metadata")
    #expect(context.observation == "delivery_launch")
    #expect(context.deliverySessionID == FileLogHandler.sessionID)
    #expect(context.appVersion == "1.4")
    #expect(context.appBuild == "612")
    #expect(context.osVersion == "iPhone OS 26.1 (23B85)")
    #expect(context.platformArchitecture == "arm64e")
    #expect(context.deviceType == "iPhone17,1")
    #expect(context.bundleIdentifier == "com.artisanalsoftware.PodHaven")
    #expect(context.pid == 4242)
    #expect(context.periodStart == payload.timeStampBegin.ISO8601Format())
    #expect(context.periodEnd == payload.timeStampEnd.ISO8601Format())
    #expect(context.exceptionType == 10)
    #expect(context.exceptionCode == 0)
    #expect(context.signal == 9)
    #expect(context.terminationReason == "Namespace FRONTBOARD, Code 0x8badf00d")
    #expect(context.objectiveCException == nil)
    #expect(context.threads == 2)
    #expect(context.omittedThreads == 0)
    #expect(context.frames == 7)
    #expect(context.truncatedThreads == 0)

    let raw = crash.jsonRepresentation()
    #expect(capture.attachmentName == "metrickit-crash-diagnostic.json")
    #expect(capture.attachmentType == "application/json")
    #expect(capture.attachment == raw)
    #expect(raw.count <= MetricKitCrashReport.maximumAttachmentBytes)
    #expect(context.rawPayloadBytes == raw.count)
    #expect(context.rawPayloadAttachment == "included")
    #expect(event.contexts.launchTimeline?.attribution == "not_retained")
    #expect(event.contexts.launchTimeline?.pid == 4242)

    let local = logs.filter { $0.message == "MetricKit crash diagnostic received" }
    #expect(local.count == 1)
    #expect(local.first?.level == .notice)
    #expect(local.first?.metadata["metricKitDiagnostic"] == String(decoding: raw, as: UTF8.self))
  }

  @Test("a forwarded crash carries the retained timeline of the launch it killed")
  func crashCarriesKilledLaunchTimeline() throws {
    let start = Date(timeIntervalSince1970: 1_789_999_000)
    Container.shared.launchProcess.register { LaunchProcess(pid: 4242, start: start) }
    Container.shared.fakeDate().freeze(at: start.addingTimeInterval(8.5))
    Container.shared.launchTimeline().record(.sentryStarted)
    Container.shared.launchProcess.register {
      LaunchProcess(pid: 5353, start: start.addingTimeInterval(7_200))
    }
    Container.shared.launchTimeline.reset(.scope)

    let captured = captures([Payload(crashReports: [Self.crash()])])

    let event = try decode(try #require(captured.first))
    let timeline = try #require(event.contexts.launchTimeline)
    #expect(timeline.attribution == "pid_match")
    #expect(timeline.pid == 4242)
    #expect(timeline.sessionID == FileLogHandler.sessionID)
    #expect(timeline.lastMilestone == "sentryStarted")
    #expect(timeline.millisecondsAfterOrigin == ["sentryStarted": 8_500])
  }

  @Test("the grouping key ignores per-occurrence values and separates termination categories")
  func groupingKeyIsStable() throws {
    var first = Self.crash(slide: 0)
    first.terminationReason =
      "Namespace FRONTBOARD, Code 0x8badf00d, application<com.artisanalsoftware.PodHaven>:101"
    var second = Self.crash(slide: 0x4c_0000)
    second.terminationReason =
      "Namespace FRONTBOARD, Code 0x8badf00d, application<com.artisanalsoftware.PodHaven>:202"
    second.exceptionCode = 7
    var killed = Self.crash()
    killed.terminationReason = nil
    let captured = captures([
      Payload(crashReports: [first]),
      Payload(
        timeStampBegin: Date(timeIntervalSince1970: 1_791_000_000),
        timeStampEnd: Date(timeIntervalSince1970: 1_791_086_400),
        crashReports: [second, killed]
      ),
    ])

    let events = try captured.map(decode)
    #expect(events.count == 3)
    #expect(events[0].fingerprint == ["{{ default }}", "metrickit-crash", "watchdog"])
    #expect(events[1].fingerprint == events[0].fingerprint)
    #expect(events[2].fingerprint == ["{{ default }}", "metrickit-crash", "sigkill"])
    #expect(events[0].exception.values.first?.type == events[1].exception.values.first?.type)
    #expect(events[0].exception.values.first?.value == events[1].exception.values.first?.value)
    let firstFrames = try #require(events[0].exception.values.first?.stacktrace?.frames)
    let secondFrames = try #require(events[1].exception.values.first?.stacktrace?.frames)
    #expect(firstFrames.map(\.package) == secondFrames.map(\.package))
    #expect(firstFrames.map(\.inApp) == secondFrames.map(\.inApp))
    #expect(firstFrames.map(\.instructionAddr) != secondFrames.map(\.instructionAddr))
  }

  // MARK: - Eligibility

  @Test(
    "kills the in-process reporter cannot observe are forwarded with their termination category",
    arguments: [
      (9, 10, nil, "sigkill"),
      (nil, nil, "Namespace SPRINGBOARD, Code 0x8badf00d", "watchdog"),
      (
        9, 10, "Namespace FRONTBOARD, Code 2343432205 scene-update watchdog transgression",
        "watchdog"
      ),
      (9, 11, nil, "resource_limit"),
      (nil, 12, "Namespace GUARD, Code 0x0", "guard"),
    ] as [(Int?, Int?, String?, String)]
  )
  func eligibleTerminations(
    signal: Int?,
    exceptionType: Int?,
    terminationReason: String?,
    expected: String
  ) throws {
    var crash = Self.crash()
    crash.signal = signal.map { NSNumber(value: $0) }
    crash.exceptionType = exceptionType.map { NSNumber(value: $0) }
    crash.terminationReason = terminationReason
    let captured = captures([Payload(crashReports: [crash])])

    #expect(captured.count == 1)
    let event = try decode(try #require(captured.first))
    #expect(event.contexts.metrickitCrash.termination == expected)
    #expect(event.contexts.metrickitCrash.signal == signal)
    #expect(event.contexts.metrickitCrash.exceptionType == exceptionType)
  }

  @Test(
    "crashes the in-process reporter captures stay local",
    arguments: [
      (11, 1, nil),
      (6, 10, nil),
      (5, 6, nil),
      (4, 2, nil),
      (15, nil, "Namespace SIGNAL, Code 0xf"),
      (nil, nil, nil),
    ] as [(Int?, Int?, String?)]
  )
  func ineligibleCrashesStayLocal(
    signal: Int?,
    exceptionType: Int?,
    terminationReason: String?
  ) throws {
    var crash = Self.crash()
    crash.signal = signal.map { NSNumber(value: $0) }
    crash.exceptionType = exceptionType.map { NSNumber(value: $0) }
    crash.terminationReason = terminationReason
    let (captured, logs) = LogCapture.withSink { sink in
      (captures([Payload(crashReports: [crash])]), sink.captured())
    }

    #expect(captured.isEmpty)
    #expect(
      logs.filter { $0.message == "MetricKit crash diagnostic received" && $0.level == .notice }
        .count == 1
    )
  }

  @Test("hang, CPU, disk-write, and launch diagnostics stay with the native integration")
  func otherDiagnosticsAreNotCaptured() {
    let categories: [MetricKitDiagnosticCategory] = [
      .hang, .cpuException, .diskWriteException, .appLaunch,
    ]
    let payload = Payload(
      otherDiagnostics: categories.map {
        MetricKitDiagnosticRecord(category: $0, json: Data(#"{"callStackTree":{}}"#.utf8))
      }
    )
    let (captured, logs) = LogCapture.withSink { sink in
      (captures([payload]), sink.captured().filter { $0.label == "PodHaven/MetricKit" })
    }

    #expect(captured.isEmpty)
    #expect(
      logs.map(\.message) == categories.map { "MetricKit \($0.rawValue) diagnostic received" }
    )
    #expect(logs.allSatisfy { $0.level == .notice })
  }

  // MARK: - Bounds

  @Test("an oversized raw payload is reported without its attachment")
  func oversizedPayloadOmitsAttachment() throws {
    var crash = Self.crash()
    crash.raw = Data(repeating: 0x20, count: MetricKitCrashReport.maximumAttachmentBytes + 1)
    let captured = captures([Payload(crashReports: [crash])])

    let capture = try #require(captured.first)
    #expect(captured.count == 1)
    #expect(capture.attachment == nil)
    let context = try decode(capture).contexts.metrickitCrash
    #expect(context.rawPayloadAttachment == "omitted_over_limit")
    #expect(context.rawPayloadBytes == MetricKitCrashReport.maximumAttachmentBytes + 1)
  }

  @Test("an Objective-C exception message never leaves the device")
  func objectiveCExceptionOmitsAttachment() throws {
    var crash = Self.crash()
    crash.objectiveCException = MetricKitObjectiveCException(
      name: "NSInternalInconsistencyException",
      className: "NSException",
      type: "NSInternalInconsistencyException"
    )
    let captured = captures([Payload(crashReports: [crash])])

    let capture = try #require(captured.first)
    #expect(capture.attachment == nil)
    let context = try decode(capture).contexts.metrickitCrash
    #expect(context.rawPayloadAttachment == "omitted_exception_message")
    #expect(context.objectiveCException?.name == "NSInternalInconsistencyException")
    #expect(context.objectiveCException?.className == "NSException")
  }

  @Test("threads, frames, and termination text stay bounded")
  func eventSizeIsBounded() throws {
    let deep = StackThread(
      attributed: true,
      frames: [Self.start]
        + (0..<(MetricKitCrashReport.maximumFramesPerThread + 20))
        .map {
          StackFrame(binary: "PodHaven", uuid: Self.appMain.uuid, offset: UInt64(0x1000 + $0))
        }
        + [Self.trap]
    )
    let threads =
      Array(repeating: Self.workerThread, count: MetricKitCrashReport.maximumThreads + 3) + [deep]
    var crash = Self.crash(threads: threads)
    crash.terminationReason = "watchdog " + String(repeating: "x", count: 5_000)
    let captured = captures([Payload(crashReports: [crash])])

    let event = try decode(try #require(captured.first))
    let context = event.contexts.metrickitCrash
    #expect(event.threads.values.count == MetricKitCrashReport.maximumThreads + 1)
    #expect(context.threads == MetricKitCrashReport.maximumThreads + 1)
    #expect(context.omittedThreads == 3)
    #expect(context.truncatedThreads == 1)
    let crashed = try #require(event.threads.values.first { $0.crashed == true })
    #expect(crashed.id == threads.count - 1)
    #expect(event.exception.values.first?.threadId == crashed.id)
    #expect(crashed.stacktrace.frames.count == MetricKitCrashReport.maximumFramesPerThread)
    #expect(crashed.stacktrace.frames.last?.package == "libsystem_kernel.dylib")
    #expect(crashed.stacktrace.frames.first?.package == "PodHaven")
    #expect(
      context.frames
        == MetricKitCrashReport.maximumThreads * Self.workerThread.frames.count
        + MetricKitCrashReport.maximumFramesPerThread
    )
    let reason = try #require(context.terminationReason)
    #expect(reason.count == MetricKitCrashReport.maximumReasonLength)
  }

  @Test("a call stack nested deeper than JSON parsers allow keeps the frames nearest the crash")
  func deepCallStackIsCaptured() throws {
    let deep = StackThread(
      attributed: true,
      frames: [Self.start]
        + (0..<1_000)
        .map {
          StackFrame(binary: "PodHaven", uuid: Self.appMain.uuid, offset: UInt64(0x1000 + $0))
        }
        + [Self.plugIn, Self.trap]
    )
    let crash = Self.crash(threads: [deep, Self.workerThread])
    let captured = captures([Payload(crashReports: [crash])])

    #expect(captured.count == 1)
    let capture = try #require(captured.first)
    let event = try decode(capture)
    let expectedFrames = Self.wireFrames(
      Array(deep.frames.suffix(MetricKitCrashReport.maximumFramesPerThread))
    )
    #expect(event.threads.values.map(\.crashed) == [true, false])
    #expect(event.threads.values.first?.stacktrace.frames == expectedFrames)
    #expect(event.exception.values.first?.stacktrace?.frames == expectedFrames)
    #expect(
      event.threads.values.last?.stacktrace.frames == Self.wireFrames(Self.workerThread.frames)
    )
    let context = event.contexts.metrickitCrash
    #expect(context.truncatedThreads == 1)
    #expect(
      context.frames
        == MetricKitCrashReport.maximumFramesPerThread + Self.workerThread.frames.count
    )
    #expect(capture.attachment == crash.jsonRepresentation())
  }

  @Test("captures per payload are capped and the overflow is logged")
  func capturesPerPayloadAreCapped() throws {
    let crash = Self.crash()
    let count = MetricKitCrashReport.maximumCapturesPerPayload + 2
    let (captured, logs) = LogCapture.withSink { sink in
      (
        captures([Payload(crashReports: Array(repeating: crash, count: count))]),
        sink.captured().filter { $0.label == "PodHaven/MetricKit" }
      )
    }

    #expect(captured.count == MetricKitCrashReport.maximumCapturesPerPayload)
    #expect(
      logs.filter { $0.message == "MetricKit crash diagnostic received" }.count == count
    )
    #expect(logs.contains { $0.level == .warning && $0.message.contains("2 eligible") })
  }

  @Test("an unreadable call stack is logged and not reported without its stack")
  func unreadableCallStackIsNotCaptured() throws {
    var crash = Self.crash()
    crash.callStackTreeJSON = Data("not json".utf8)
    let (captured, logs) = LogCapture.withSink { sink in
      (captures([Payload(crashReports: [crash])]), sink.captured())
    }

    #expect(captured.isEmpty)
    #expect(logs.contains { $0.level == .error && $0.message.contains("watchdog") })
  }
}
