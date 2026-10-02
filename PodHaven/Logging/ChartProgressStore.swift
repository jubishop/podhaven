// Copyright Justin Bishop, 2026

import Darwin
import Foundation
import Logging

struct ChartProgressSession: Codable, Sendable {
  let sessionID: String
  let version: String
  let buildNumber: String
  let gitCommitHash: String
  var started: Double = Date().timeIntervalSince1970
}

// Shared mapped pages survive process termination without a write/JSON operation per render.
// This protects native-crash evidence, not against power loss or filesystem failure.
struct ChartProgressStore: Sendable {
  static let instanceCapacity = 32
  static let historyCapacity = 8
  static let evictionCapacity = 32
  static let sessionCapacity = 4
  static let headerBytes = 4096
  static let recordBytes = 512
  static let fileBytes =
    headerBytes
    + (instanceCapacity * historyCapacity + evictionCapacity) * recordBytes

  private static let sources = ["download", "playback", "opml", "preview"]
  private static let transitions = ["render", "transaction", "appeared", "disappeared", "scene"]
  private static let scenes = ["unknown", "active", "inactive", "background"]
  private static let geometries = ["unmeasured", "current_render", "last_render"]
  private let state: ThreadSafe<Storage>
  private let directory: URL
  private let session: ChartProgressSession
  private static let log = Log.as("ChartProgressStore")

  init(directory: URL, session: ChartProgressSession) throws {
    self.directory = directory
    self.session = session
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let files = try FileManager.default
      .contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.creationDateKey]
      )
      .filter { $0.pathExtension == "bin" }
    let dated =
      try files.map {
        ($0, try $0.resourceValues(forKeys: [.creationDateKey]).creationDate ?? .distantPast)
      }
      .sorted { $0.1 < $1.1 }
    let removed = dated.prefix(max(0, files.count - Self.sessionCapacity + 1))
    let header = try JSONEncoder().encode(session)
    guard header.count < 2040 else { throw StoreError.invalidHeader }
    let storage = try Storage(url: directory.appendingPathComponent(session.sessionID + ".bin"))
    unsafe storage.memory.storeBytes(of: UInt64(header.count), as: UInt64.self)
    unsafe header.withUnsafeBytes { bytes in
      if let base = bytes.baseAddress {
        unsafe storage.memory.advanced(by: 8).copyMemory(from: base, byteCount: bytes.count)
      }
    }
    unsafe storage.memory.storeBytes(of: UInt64(removed.count), toByteOffset: 2048, as: UInt64.self)
    for (url, _) in removed { try FileManager.default.removeItem(at: url) }
    state = ThreadSafe(storage)
  }

  func record(_ snapshot: ChartProgressSnapshot) {
    state { storage in
      let index: Int
      if let existing = storage.instances[snapshot.instance] {
        index = existing.index
      } else if storage.instances.count < Self.instanceCapacity {
        index = storage.instances.count
      } else {
        guard
          let victim = storage.instances.min(by: { left, right in
            if left.value.terminal != right.value.terminal { return left.value.terminal }
            return left.value.order < right.value.order
          })
        else { return }
        index = victim.value.index
        let prior = victim.value.snapshot
        let evictionIndex =
          Self.instanceCapacity * Self.historyCapacity
          + Int(storage.evictions % UInt64(Self.evictionCapacity))
        unsafe Self.write(prior, to: storage.memory, index: evictionIndex)
        storage.evictions += 1
        unsafe storage.memory.storeBytes(of: storage.evictions, toByteOffset: 2056, as: UInt64.self)
        let source = Self.sources.firstIndex(of: prior.source.rawValue) ?? 3
        storage.evictionsBySource[source] += 1
        unsafe storage.memory.storeBytes(
          of: storage.evictionsBySource[source],
          toByteOffset: 2064 + source * 8,
          as: UInt64.self
        )
        storage.instances.removeValue(forKey: victim.key)
        // Clear the retired occupant's history before publishing the new occupant.
        unsafe storage.memory
          .advanced(by: Self.headerBytes + index * Self.historyCapacity * Self.recordBytes)
          .initializeMemory(
            as: UInt8.self,
            repeating: 0,
            count: Self.historyCapacity * Self.recordBytes
          )
      }
      storage.order += 1
      storage.instances[snapshot.instance] = Occupant(
        index: index,
        order: storage.order,
        terminal: snapshot.transition == "disappeared",
        snapshot: snapshot
      )
      unsafe Self.write(
        snapshot,
        to: storage.memory,
        index: index * Self.historyCapacity + (snapshot.sequence - 1) % Self.historyCapacity
      )
    }
  }

  func export(sessionID: String) throws -> Data {
    guard UUID(uuidString: sessionID) != nil else { throw StoreError.invalidSession }
    let bytes: Data
    if sessionID == session.sessionID {
      bytes = state { unsafe Data(bytes: $0.memory, count: Self.fileBytes) }
    } else {
      let url = directory.appendingPathComponent(sessionID + ".bin")
      guard FileManager.default.fileExists(atPath: url.path) else {
        if let legacy = try legacyEvidence(sessionID: sessionID) { return legacy }
        return try Self.line([
          "kind": "unavailable", "sessionID": sessionID, "reason": "session_not_retained",
          "sessionCapacity": Self.sessionCapacity,
        ])
      }
      bytes = try Data(contentsOf: url)
    }
    guard bytes.count == Self.fileBytes else { throw StoreError.invalidHeader }
    let rawLength = unsafe bytes.withUnsafeBytes { unsafe $0.loadUnaligned(as: UInt64.self) }
    guard (1..<2040).contains(rawLength) else { throw StoreError.invalidHeader }
    let length = Int(rawLength)
    let metadata = try JSONDecoder()
      .decode(ChartProgressSession.self, from: bytes.subdata(in: 8..<(8 + length)))
    guard metadata.sessionID == sessionID else { throw StoreError.invalidSession }
    var snapshots: [ChartProgressSnapshot] = []
    var evicted: [ChartProgressSnapshot] = []
    var invalidRecords: [Int] = []
    unsafe bytes.withUnsafeBytes { raw in
      for index in 0..<(Self.instanceCapacity * Self.historyCapacity + Self.evictionCapacity) {
        let words = (0..<64)
          .map {
            unsafe raw.loadUnaligned(
              fromByteOffset: Self.headerBytes + index * Self.recordBytes + $0 * 8,
              as: UInt64.self
            )
          }
        if words.allSatisfy({ $0 == 0 }) { continue }
        guard words[63] == Self.checksum(words.prefix(63)), let snapshot = Self.decode(words) else {
          invalidRecords.append(index)
          continue
        }
        if index < Self.instanceCapacity * Self.historyCapacity {
          snapshots.append(snapshot)
        } else {
          evicted.append(snapshot)
        }
      }
    }
    let groups = Dictionary(grouping: snapshots, by: \.instance)
    let freshness = groups.keys.sorted { $0.uuidString < $1.uuidString }
      .compactMap { id -> [String: Any]? in
        guard let rows = groups[id] else { return nil }
        let ordered = rows.sorted { $0.sequence < $1.sequence }
        guard let first = ordered.first, let last = ordered.last else { return [:] }
        return [
          "instance": last.instance.uuidString, "source": last.source.rawValue,
          "firstSequence": first.sequence, "latestSequence": last.sequence,
          "latestRevision": last.revision, "latestTimestamp": last.timestamp,
          "omittedTransitions": max(0, last.sequence - rows.count),
          "terminal": last.transition == "disappeared",
        ]
      }
    var summary: [String: Any] = [
      "kind": "retention", "schema": 2, "sessionID": sessionID,
      "version": metadata.version, "buildNumber": metadata.buildNumber,
      "gitCommitHash": metadata.gitCommitHash, "timestamp": metadata.started,
      "instanceCapacity": Self.instanceCapacity, "historyCapacity": Self.historyCapacity,
      "evictionCapacity": Self.evictionCapacity, "sessionCapacity": Self.sessionCapacity,
      "mappedBytes": Self.fileBytes, "attachmentLimitBytes": ChartProgressDiagnostics.maximumBytes,
      "invalidRecords": invalidRecords.count, "invalidRecordSlots": invalidRecords,
      "instances": freshness,
      "evictedInstances": evicted.map {
        [
          "instance": $0.instance.uuidString, "source": $0.source.rawValue,
          "latestSequence": $0.sequence, "latestRevision": $0.revision,
          "latestTimestamp": $0.timestamp, "terminal": $0.transition == "disappeared",
        ] as [String: Any]
      },
    ]
    unsafe bytes.withUnsafeBytes { raw in
      summary["evictedSessionsAtLaunch"] = unsafe raw.loadUnaligned(
        fromByteOffset: 2048,
        as: UInt64.self
      )
      let count = unsafe raw.loadUnaligned(fromByteOffset: 2056, as: UInt64.self)
      summary["evictions"] = count
      summary["omittedEvictionDetails"] = max(0, Int(clamping: count) - evicted.count)
      summary["evictionsBySource"] = Dictionary(
        uniqueKeysWithValues: Self.sources.enumerated()
          .map {
            unsafe (
              $0.element, raw.loadUnaligned(fromByteOffset: 2064 + $0.offset * 8, as: UInt64.self)
            )
          }
      )
    }
    var result = try Self.line(summary)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.nonConformingFloatEncodingStrategy = .convertToString(
      positiveInfinity: "+Infinity",
      negativeInfinity: "-Infinity",
      nan: "NaN"
    )
    for snapshot in snapshots.sorted(by: {
      ($0.timestamp, $0.sequence) < ($1.timestamp, $1.sequence)
    }) {
      let chart = try encoder.encode(snapshot)
      result.append(
        try Self.line([
          "kind": "snapshot", "sessionID": sessionID, "version": metadata.version,
          "buildNumber": metadata.buildNumber, "gitCommitHash": metadata.gitCommitHash,
          "timestamp": snapshot.timestamp,
          "metadata": ["chart": String(decoding: chart, as: UTF8.self)],
        ])
      )
    }
    guard result.count <= ChartProgressDiagnostics.maximumBytes else {
      throw StoreError.exportOverflow
    }
    return result
  }

  private func legacyEvidence(sessionID: String) throws -> Data? {
    let url = directory.deletingLastPathComponent().appendingPathComponent("chart-progress.ndjson")
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    guard let size = attributes[.size] as? NSNumber, size.intValue <= 64 * 1024 else {
      throw StoreError.invalidHeader
    }
    let contents = try Data(contentsOf: url)
    var result = Data()
    for line in contents.split(separator: 0x0A) {
      let record = try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
      if record?["sessionID"] as? String == sessionID {
        result.append(contentsOf: line)
        result.append(0x0A)
      }
    }
    return result.isEmpty ? nil : result
  }

  private static func line(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) + Data([0x0A])
  }

  private static func checksum(_ words: ArraySlice<UInt64>) -> UInt64 {
    words.reduce(0xcbf2_9ce4_8422_2325) { ($0 ^ $1) &* 0x100_0000_01b3 }
  }

  private static func write(
    _ snapshot: ChartProgressSnapshot,
    to memory: UnsafeMutableRawPointer,
    index: Int
  ) {
    var words = [UInt64](repeating: 0, count: 64)
    words[0] = 2
    withUnsafeBytes(of: snapshot.instance.uuid) {
      words[1] = unsafe $0.loadUnaligned(as: UInt64.self)
      words[2] = unsafe $0.loadUnaligned(fromByteOffset: 8, as: UInt64.self)
    }
    words[3] = UInt64(snapshot.revision)
    words[4] = UInt64(snapshot.sequence)
    words[5] = snapshot.timestamp.bitPattern
    words[6] = snapshot.uptime.bitPattern
    words[7] = UInt64(sources.firstIndex(of: snapshot.source.rawValue) ?? 3)
    words[8] = UInt64(transitions.firstIndex(of: snapshot.transition) ?? 0)
    words[9] = UInt64(scenes.firstIndex(of: snapshot.scene) ?? 0)
    words[10] = UInt64(geometries.firstIndex(of: snapshot.geometryObservation) ?? 0)
    words[11] = snapshot.total.bitPattern
    words[12] = snapshot.sum.bitPattern
    words[13] = UInt64(snapshot.sectorCount)
    words[14] = snapshot.innerRadiusRatio.bitPattern
    let optionals = [
      snapshot.width, snapshot.height, snapshot.angularInset, snapshot.numerator,
      snapshot.denominator,
    ]
    for (index, value) in optionals.enumerated() {
      if let value {
        words[15] |= 1 << index
        words[16 + index] = value.bitPattern
      }
    }
    if let waiting = snapshot.waitingCount {
      words[15] |= 1 << 5
      words[21] = UInt64(bitPattern: Int64(waiting))
    }
    words[22] = snapshot.animationPresent == nil ? 0 : (snapshot.animationPresent == true ? 2 : 1)
    words[23] =
      snapshot.animationsDisabled == nil ? 0 : (snapshot.animationsDisabled == true ? 2 : 1)
    words[24] = UInt64(snapshot.values.count)
    words[25] = UInt64(snapshot.sectorKeys.count)
    words[26] = snapshot.proportions == nil ? 0 : 1
    for (index, value) in snapshot.values.enumerated() { words[27 + index] = value.bitPattern }
    for (index, key) in snapshot.sectorKeys.enumerated() {
      words[35 + index] = UInt64(bitPattern: Int64(key))
    }
    words[63] = checksum(words.prefix(63))
    let address = unsafe memory.advanced(by: headerBytes + index * recordBytes)
    unsafe address.storeBytes(of: UInt64(0), toByteOffset: 63 * 8, as: UInt64.self)
    words.withUnsafeBytes { bytes in
      if let base = bytes.baseAddress { unsafe address.copyMemory(from: base, byteCount: 63 * 8) }
    }
    unsafe address.storeBytes(of: words[63], toByteOffset: 63 * 8, as: UInt64.self)
  }

  private static func decode(_ words: [UInt64]) -> ChartProgressSnapshot? {
    guard words[0] == 2, words[3] <= UInt64(Int.max), words[4] > 0, words[4] <= UInt64(Int.max),
      words[7] < sources.count, words[8] < transitions.count, words[9] < scenes.count,
      words[10] < geometries.count, words[13] <= UInt64(Int.max), words[24] <= 8, words[25] <= 8,
      let source = ChartProgressInput.Source(rawValue: sources[Int(words[7])])
    else { return nil }
    let uuid = words.withUnsafeBytes {
      unsafe UUID(uuid: $0.loadUnaligned(fromByteOffset: 8, as: uuid_t.self))
    }
    func optional(_ index: Int) -> Double? {
      words[15] & (1 << index) == 0 ? nil : Double(bitPattern: words[16 + index])
    }
    let size: CGSize?
    if let width = optional(0), let height = optional(1) {
      size = CGSize(width: width, height: height)
    } else {
      size = nil
    }
    return ChartProgressSnapshot(
      input: ChartProgressInput(
        source: source,
        total: Double(bitPattern: words[11]),
        values: (0..<Int(words[24])).map { Double(bitPattern: words[27 + $0]) },
        sectorKeys: (0..<Int(words[25])).map { Int(bitPattern: UInt(words[35 + $0])) },
        innerRadiusRatio: Double(bitPattern: words[14]),
        angularInset: optional(2),
        numerator: optional(3),
        denominator: optional(4),
        waitingCount: words[15] & (1 << 5) == 0 ? nil : Int(bitPattern: UInt(words[21]))
      ),
      instance: uuid,
      revision: Int(words[3]),
      sequence: Int(words[4]),
      transition: transitions[Int(words[8])],
      size: size,
      scene: scenes[Int(words[9])],
      animationPresent: words[22] == 0 ? nil : words[22] == 2,
      animationsDisabled: words[23] == 0 ? nil : words[23] == 2,
      timestamp: Double(bitPattern: words[5]),
      uptime: Double(bitPattern: words[6]),
      sectorCount: Int(words[13]),
      sum: Double(bitPattern: words[12]),
      valuesValid: words[26] == 1,
      geometryObservation: geometries[Int(words[10])]
    )
  }

  private struct Occupant {
    let index: Int
    let order: UInt64
    let terminal: Bool
    let snapshot: ChartProgressSnapshot
  }

  @safe private final class Storage {
    let memory: UnsafeMutableRawPointer
    var instances: [UUID: Occupant] = [:]
    var order: UInt64 = 0
    var evictions: UInt64 = 0
    var evictionsBySource: [UInt64] = [0, 0, 0, 0]

    init(url: URL) throws {
      let descriptor = unsafe open(url.path, O_RDWR | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
      guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
      defer {
        if close(descriptor) != 0 {
          log.error("Could not close chart mapping descriptor: errno \(errno)")
        }
      }
      guard ftruncate(descriptor, off_t(fileBytes)) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
      }
      guard
        let mapping = unsafe mmap(
          nil,
          fileBytes,
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
      if unsafe munmap(memory, fileBytes) != 0 {
        log.error("Could not release chart mapping: errno \(errno)")
      }
    }
  }

  private enum StoreError: Error {
    case invalidHeader, invalidSession, exportOverflow
  }
}
