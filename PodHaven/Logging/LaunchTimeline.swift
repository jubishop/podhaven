// Copyright Justin Bishop, 2026

import Darwin
import FactoryKit
import Foundation
import Logging

extension Container {
  var launchProcess: Factory<LaunchProcess> {
    Factory(self) { LaunchProcess.current() }.scope(.cached)
  }

  var launchTimeline: Factory<LaunchTimeline> {
    Factory(self) { LaunchTimeline() }.scope(.cached)
  }
}

struct LaunchProcess: Sendable {
  let pid: Int32
  let start: Date?
  let prewarmed: Bool

  static func current() -> LaunchProcess {
    let pid = getpid()
    let prewarmed = ProcessInfo.processInfo.environment["ActivePrewarm"] == "1"
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    var info = unsafe kinfo_proc()
    var size = unsafe MemoryLayout<kinfo_proc>.stride
    guard unsafe sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0
    else { return LaunchProcess(pid: pid, start: nil, prewarmed: prewarmed) }
    let start = unsafe info.kp_proc.p_starttime
    return LaunchProcess(
      pid: pid,
      start: Date(
        timeIntervalSince1970: Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000
      ),
      prewarmed: prewarmed
    )
  }
}

// Each launch's milestones live in shared mapped pages, which the kernel keeps
// after a watchdog's SIGKILL, so recording one costs no write, encoding, or
// queue hop. A later launch matches them to a MetricKit crash by pid.
struct LaunchTimeline: Sendable {
  enum Milestone: String, CaseIterable, Sendable {
    case didFinishLaunching
    case loggingStarted
    case logsOpened
    case logsFlushed
    case sentryStarted
    case databaseOpened
    case backgroundTasksRegistered
    case audioConfigured
    case bootstrapReturned
    case firstScenePhase
    case firstScenePhaseHandled
    case siriCatalogPublicationStarted
    case siriCatalogPublicationFinished
  }

  static let capacity = 16
  static let fileBytes = 4096
  private static let headerLimit = 2048
  private static let maximumFieldLength = 64
  private static let fileExtension = "launch"
  private static let log = Log.as("LaunchTimeline")

  private struct Header: Codable {
    let pid: Int32
    let processStart: Double?
    let prewarmed: Bool
    let sessionID: String
    let version: String
    let buildNumber: String
    let gitCommitHash: String
    let milestones: [String]
  }

  private struct Launch {
    let header: Header
    let marks: [(milestone: String, time: Double)]

    var start: Date? {
      guard let processStart = header.processStart else { return nil }
      return Date(timeIntervalSince1970: processStart)
    }
  }

  private enum TimelineError: Error {
    case headerTooLarge(Int)
    case invalidRecord
  }

  private let directory: URL
  private let fileName: String?
  private let mapping: ThreadSafe<Mapping?>
  private let dateProvider: any DateProviding

  fileprivate init() {
    let process = Container.shared.launchProcess()
    let dateProvider = Container.shared.dateProvider()
    let directory = AppInfo.documentsDirectory
      .appendingPathComponent("launch-timelines", isDirectory: true)
    self.dateProvider = dateProvider
    self.directory = directory
    let millis = String(Int64((process.start ?? dateProvider.now).timeIntervalSince1970 * 1_000))
    let fileName =
      String(repeating: "0", count: max(0, 15 - millis.count)) + millis
      + "-\(process.pid).\(Self.fileExtension)"
    let header = Header(
      pid: process.pid,
      processStart: process.start?.timeIntervalSince1970,
      prewarmed: process.prewarmed,
      sessionID: FileLogHandler.sessionID,
      version: AppInfo.version,
      buildNumber: AppInfo.buildNumber,
      gitCommitHash: AppInfo.gitCommitHash,
      milestones: Milestone.allCases.map(\.rawValue)
    )
    let mapping: Mapping?
    do {
      mapping = try Self.create(directory.appendingPathComponent(fileName), header: header)
    } catch {
      Self.log.caughtError("Could not create this launch's timeline", error)
      mapping = nil
    }
    self.fileName = mapping == nil ? nil : fileName
    self.mapping = ThreadSafe(mapping)
  }

  func record(_ milestone: Milestone) {
    record(milestone, at: dateProvider.now)
  }

  func record(_ milestone: Milestone, at time: Date) {
    guard let index = Milestone.allCases.firstIndex(of: milestone) else { return }
    let offset = Self.headerLimit + index * MemoryLayout<Double>.stride
    let seconds = time.timeIntervalSince1970
    mapping { mapping in
      guard let mapping,
        unsafe mapping.memory.load(fromByteOffset: offset, as: Double.self) == 0
      else { return }
      unsafe mapping.memory.storeBytes(of: seconds, toByteOffset: offset, as: Double.self)
    }
  }

  // The latest retained earlier launch with the crashed pid that started by the
  // diagnostic's end, so a pid reused after a reboot or the crash isn't matched.
  func crashContext(pid: Int32, endingBy end: Date) -> [String: Any] {
    let urls: [URL]
    do {
      urls = try Self.records(in: directory).filter { $0.lastPathComponent != fileName }
    } catch {
      Self.log.caughtError("Could not list retained launch timelines", error)
      return ["attribution": "unavailable", "pid": pid]
    }
    var launches: [Launch] = []
    var unreadable = 0
    for url in urls {
      do {
        launches.append(try Self.launch(from: Data(contentsOf: url)))
      } catch {
        unreadable += 1
        Self.log.caughtError("Could not read launch timeline \(url.lastPathComponent)", error)
      }
    }
    let candidates = launches.filter { launch in
      launch.header.pid == pid && (launch.start ?? .distantPast) <= end
    }
    guard
      let launch = candidates.max(by: {
        ($0.start ?? .distantPast) < ($1.start ?? .distantPast)
      })
    else {
      return [
        "attribution": "not_retained",
        "pid": pid,
        "retainedLaunches": launches.count,
        "unreadableLaunches": unreadable,
      ]
    }

    var context: [String: Any] = [
      "attribution": "pid_match",
      "pid": pid,
      "prewarmed": launch.header.prewarmed,
      "sessionID": Self.bounded(launch.header.sessionID),
      "appVersion": Self.bounded(launch.header.version),
      "appBuild": Self.bounded(launch.header.buildNumber),
      "gitCommitHash": Self.bounded(launch.header.gitCommitHash),
      "retainedLaunches": launches.count,
      "unreadableLaunches": unreadable,
      "lastMilestone": launch.marks.last?.milestone ?? "none",
    ]
    // Sentry returns fractional context numbers as strings, so offsets are whole milliseconds.
    if let origin = launch.header.processStart ?? launch.marks.first?.time {
      context["origin"] = launch.header.processStart == nil ? "firstMilestone" : "processStart"
      context["originTimestamp"] = Date(timeIntervalSince1970: origin)
        .ISO8601Format(.init(includingFractionalSeconds: true))
      context["millisecondsAfterOrigin"] = Dictionary(
        launch.marks.map { ($0.milestone, Int((($0.time - origin) * 1_000).rounded())) },
        uniquingKeysWith: { first, _ in first }
      )
    }
    return context
  }

  // MARK: - Records

  private static func create(_ url: URL, header: Header) throws -> Mapping {
    let directory = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try prune(directory, keeping: capacity - 1)
    let encoded = try JSONEncoder().encode(header)
    guard encoded.count <= headerLimit - 8 else {
      throw TimelineError.headerTooLarge(encoded.count)
    }
    let mapping = try Mapping(url: url)
    unsafe mapping.memory.storeBytes(of: UInt64(encoded.count), as: UInt64.self)
    unsafe encoded.withUnsafeBytes { bytes in
      if let base = bytes.baseAddress {
        unsafe mapping.memory.advanced(by: 8).copyMemory(from: base, byteCount: bytes.count)
      }
    }
    return mapping
  }

  private static func records(in directory: URL) throws -> [URL] {
    try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == fileExtension }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
  }

  private static func prune(_ directory: URL, keeping count: Int) throws {
    let records = try records(in: directory)
    for url in records.prefix(max(0, records.count - count)) {
      try FileManager.default.removeItem(at: url)
    }
  }

  private static func launch(from data: Data) throws -> Launch {
    guard data.count == fileBytes else { throw TimelineError.invalidRecord }
    let length = Int(unsafe data.withUnsafeBytes { unsafe $0.loadUnaligned(as: UInt64.self) })
    guard (1...headerLimit - 8).contains(length) else { throw TimelineError.invalidRecord }
    let header = try JSONDecoder().decode(Header.self, from: data.subdata(in: 8..<8 + length))
    let slots = (fileBytes - headerLimit) / MemoryLayout<Double>.stride
    let marks = header.milestones.prefix(slots).enumerated()
      .compactMap { index, milestone -> (milestone: String, time: Double)? in
        let offset = headerLimit + index * MemoryLayout<Double>.stride
        let time = unsafe data.withUnsafeBytes {
          unsafe $0.loadUnaligned(fromByteOffset: offset, as: Double.self)
        }
        guard time > 0 else { return nil }
        return (bounded(milestone), time)
      }
      .sorted { $0.time < $1.time }
    return Launch(header: header, marks: marks)
  }

  private static func bounded(_ value: String) -> String {
    String(value.prefix(maximumFieldLength))
  }

  // MARK: - Mapping

  @safe private final class Mapping {
    let memory: UnsafeMutableRawPointer

    init(url: URL) throws {
      let descriptor = unsafe open(url.path, O_RDWR | O_CREAT | O_TRUNC, S_IRUSR | S_IWUSR)
      guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
      defer {
        if close(descriptor) != 0 {
          LaunchTimeline.log.error("Could not close launch timeline descriptor: errno \(errno)")
        }
      }
      guard ftruncate(descriptor, off_t(LaunchTimeline.fileBytes)) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
      }
      guard
        let mapping = unsafe mmap(
          nil,
          LaunchTimeline.fileBytes,
          PROT_READ | PROT_WRITE,
          MAP_SHARED,
          descriptor,
          0
        ),
        unsafe mapping != MAP_FAILED
      else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
      unsafe memory = unsafe mapping
    }

    deinit {
      if unsafe munmap(memory, LaunchTimeline.fileBytes) != 0 {
        LaunchTimeline.log.error("Could not release launch timeline mapping: errno \(errno)")
      }
    }
  }
}
