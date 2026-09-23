// Copyright Justin Bishop, 2026

import Foundation
import Intents
import Logging
import Synchronization

final class SiriMediaIntentHandler: NSObject, INPlayMediaIntentHandling, Sendable {
  typealias Completion = @Sendable (INPlayMediaIntentResponse) -> Void
  typealias PlaybackSelection = @MainActor @Sendable (SiriMediaSelection?) -> Void
  typealias Playback = @MainActor @Sendable (@escaping Completion) -> PlaybackSelection
  private let catalog: @Sendable () async throws -> SiriCatalog
  private let authorized: @Sendable () -> Bool
  private let playback: Playback?
  private let diagnostic: @Sendable (SiriResolutionOperation.Summary) -> Void
  private let latestHandle = Mutex<UUID?>(nil)
  private static let log = Log.as("SiriMediaIntentHandler")

  init(
    catalog: @escaping @Sendable () async throws -> SiriCatalog,
    authorized: @escaping @Sendable () -> Bool,
    diagnostic: @escaping @Sendable (SiriResolutionOperation.Summary) -> Void = { _ in },
    playback: Playback? = nil
  ) {
    self.catalog = catalog
    self.authorized = authorized
    self.diagnostic = diagnostic
    self.playback = playback
  }

  func resolveMediaItems(
    for intent: INPlayMediaIntent,
    with completion: @escaping @Sendable ([INPlayMediaMediaItemResolutionResult]) -> Void
  ) {
    let request = Result { try SiriMediaRequest(intent) }
    let operation = SiriResolutionOperation(mode: "resolve", intent: intent, report: diagnostic)
    Task { @MainActor in
      do {
        let (_, entries) = try await Self.lookup(
          request,
          catalog: catalog,
          authorized: authorized,
          operation: operation
        )
        guard authorized() else { throw SiriMediaFailure.unauthorized }
        let results = try await Self.resolutionResults(entries)
        guard authorized() else { throw SiriMediaFailure.unauthorized }
        completion(results)
      } catch SiriMediaFailure.needsName {
        completion([.needsValue()])
      } catch SiriMediaFailure.unauthorized {
        completion([.unsupported(forReason: .restrictedContent)])
      } catch {
        Self.log.caughtError("Siri media resolution failed", error)
        completion([.unsupported()])
      }
    }
  }

  @concurrent private static func resolutionResults(_ entries: [SiriCatalog.Entry]) async throws
    -> sending [INPlayMediaMediaItemResolutionResult]
  {
    let items = try entries.map { try $0.mediaItem() }
    if items.count == 1 { return INPlayMediaMediaItemResolutionResult.successes(with: items) }
    return [.disambiguation(with: items)]
  }

  func confirm(intent: INPlayMediaIntent, completion: @escaping Completion) {
    select(intent, mode: "confirm", completion: completion)
  }

  func handle(intent: INPlayMediaIntent, completion: @escaping Completion) {
    select(intent, mode: "handle", completion: completion)
  }

  private func select(_ intent: INPlayMediaIntent, mode: String, completion: @escaping Completion) {
    let request = Result { try SiriMediaRequest(intent) }
    let operation = SiriResolutionOperation(mode: mode, intent: intent, report: diagnostic)
    let id = UUID()
    if mode == "handle" { latestHandle.withLock { $0 = id } }
    Task { @MainActor in
      guard mode != "handle" || latestHandle.withLock({ $0 == id }) else {
        completion(INPlayMediaIntentResponse(code: .failure, userActivity: nil))
        return
      }
      let acceptSelection = mode == "handle" ? playback?(completion) : nil
      do {
        let (generation, matches) = try await Self.lookup(
          request,
          catalog: catalog,
          authorized: authorized,
          operation: operation
        )
        guard authorized() else { throw SiriMediaFailure.unauthorized }
        guard matches.count == 1, let entry = matches.first else {
          throw SiriMediaFailure.ambiguous
        }
        if mode == "confirm" {
          completion(INPlayMediaIntentResponse(code: .ready, userActivity: nil))
          return
        }
        guard latestHandle.withLock({ $0 == id }) else { throw CancellationError() }
        let selected = SiriMediaSelection(
          identity: entry.identity,
          title: entry.displayTitle,
          catalogGeneration: generation
        )
        if let acceptSelection {
          acceptSelection(selected)
        } else {
          completion(INPlayMediaIntentResponse(code: .handleInApp, userActivity: nil))
        }
      } catch {
        Self.log.caughtError("Siri media selection failed", error)
        if let acceptSelection {
          acceptSelection(nil)
        } else {
          completion(INPlayMediaIntentResponse(code: .failure, userActivity: nil))
        }
      }
    }
  }

  @concurrent private static func lookup(
    _ request: Result<SiriMediaRequest, any Error>,
    catalog: @Sendable () async throws -> SiriCatalog,
    authorized: @Sendable () -> Bool,
    operation: SiriResolutionOperation
  ) async throws -> (UUID, [SiriCatalog.Entry]) {
    try await SiriResolutionOperation.$current.withValue(operation) {
      do {
        guard authorized() else { throw SiriMediaFailure.unauthorized }
        let request = try request.get()
        let snapshot = try await catalog()
        operation.begin(.match)
        let entries = try snapshot.matches(request)
        operation.finish(outcome: entries.count == 1 ? "unique" : "ambiguous")
        return (snapshot.generation, entries)
      } catch {
        let outcome: String
        switch error {
        case SiriMediaFailure.noMatch: outcome = "noMatch"
        case SiriMediaFailure.needsName: outcome = "needsName"
        case SiriMediaFailure.unsupported: outcome = "unsupported"
        case SiriMediaFailure.unauthorized: outcome = "unauthorized"
        default: outcome = "failed"
        }
        operation.finish(outcome: outcome)
        throw error
      }
    }
  }
}

final class SiriResolutionOperation: Sendable {
  enum Phase: String, Codable, Sendable { case queued, read, decode, match, finished }

  struct Summary: Codable, Sendable {
    let operationID: UUID
    let startedAt: Date
    let mode: String
    let requestMode: String
    let mediaType: Int
    let callbackMainThread: Bool
    var workerMainThread = false
    var phase = Phase.queued
    var readMs = 0.0
    var decodeMs = 0.0
    var matchMs = 0.0
    var totalMs = 0.0
    var bytes = 0
    var entries = 0
    var maxTitleBytes = 0
    var outcome = "pending"
  }

  @TaskLocal static var current: SiriResolutionOperation?
  private let state: Mutex<Summary>
  private let started = ProcessInfo.processInfo.systemUptime
  private let phaseStarted = Mutex(ProcessInfo.processInfo.systemUptime)
  private let report: @Sendable (Summary) -> Void
  private static let log = Log.as("SiriResolution")

  init(mode: String, intent: INPlayMediaIntent, report: @escaping @Sendable (Summary) -> Void) {
    let selected = intent.mediaItems?.first ?? intent.mediaContainer
    state = Mutex(
      Summary(
        operationID: UUID(),
        startedAt: Date(),
        mode: mode,
        requestMode: (selected?.identifier ?? intent.mediaSearch?.mediaIdentifier) == nil
          ? "name" : "identifier",
        mediaType: (intent.mediaSearch?.mediaType ?? selected?.type ?? .unknown).rawValue,
        callbackMainThread: Thread.isMainThread
      )
    )
    self.report = report
  }

  func begin(_ phase: Phase) {
    let now = ProcessInfo.processInfo.systemUptime
    let elapsed = phaseStarted.withLock { previous in
      defer { previous = now }
      return (now - previous) * 1_000
    }
    let summary = state.withLock { summary in
      switch summary.phase {
      case .read: summary.readMs += elapsed
      case .decode: summary.decodeMs += elapsed
      case .match: summary.matchMs += elapsed
      case .queued, .finished: break
      }
      summary.totalMs = (now - started) * 1_000
      summary.workerMainThread = summary.workerMainThread || Thread.isMainThread
      summary.phase = phase
      return summary
    }
    report(summary)
  }

  func readBytes(_ count: Int) { state.withLock { $0.bytes = count } }

  func decoded(_ catalog: SiriCatalog) {
    state.withLock { summary in
      summary.entries = catalog.entries.count
      summary.maxTitleBytes = catalog.entries.reduce(0) {
        max($0, $1.title.utf8.count, $1.podcastTitle?.utf8.count ?? 0)
      }
    }
  }

  func finish(outcome: String) {
    state.withLock { $0.outcome = outcome }
    begin(.finished)
    let summary = state.withLock { $0 }
    Self.log.debug(
      "Siri catalog operation completed",
      metadata: [
        "operationID": .string(summary.operationID.uuidString),
        "mode": .string(summary.mode), "requestMode": .string(summary.requestMode),
        "mediaType": .stringConvertible(summary.mediaType),
        "readMs": .stringConvertible(summary.readMs),
        "decodeMs": .stringConvertible(summary.decodeMs),
        "matchMs": .stringConvertible(summary.matchMs),
        "totalMs": .stringConvertible(summary.totalMs),
        "bytes": .stringConvertible(summary.bytes), "entries": .stringConvertible(summary.entries),
        "maxTitleBytes": .stringConvertible(summary.maxTitleBytes),
        "callbackMainThread": .stringConvertible(summary.callbackMainThread),
        "workerMainThread": .stringConvertible(summary.workerMainThread),
        "outcome": .string(summary.outcome),
      ]
    )
  }
}

final class SiriResolutionJournal: Sendable {
  struct Record: Codable, Sendable {
    let summary: SiriResolutionOperation.Summary
    let sessionID: String
    let version: String
    let build: String
    let commit: String
    let process: String
  }

  static let maximumBytes = 16 * 1024
  private let url: URL
  private let sessionID: String
  private let version: String
  private let build: String
  private let commit: String
  private let process: String
  private let lock = Mutex(())
  private static let log = Log.as("SiriResolutionJournal")

  init(url: URL, sessionID: String, version: String, build: String, commit: String, process: String)
  {
    self.url = url
    self.sessionID = sessionID
    self.version = version
    self.build = build
    self.commit = commit
    self.process = process
  }

  func record(_ summary: SiriResolutionOperation.Summary) {
    lock.withLock { _ in
      var records = read()
      records.removeAll { $0.summary.operationID == summary.operationID }
      records.append(
        Record(
          summary: summary,
          sessionID: sessionID,
          version: version,
          build: build,
          commit: commit,
          process: process
        )
      )
      records = Array(records.suffix(16))
      do {
        var data = try JSONEncoder().encode(records)
        while data.count > Self.maximumBytes && !records.isEmpty {
          records.removeFirst()
          data = try JSONEncoder().encode(records)
        }
        try FileManager.default.createDirectory(
          at: url.deletingLastPathComponent(),
          withIntermediateDirectories: true
        )
        try data.write(
          to: url,
          options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
      } catch {
        Self.log.caughtError("Could not retain Siri resolution summary", error)
      }
    }
  }

  func read() -> [Record] {
    guard FileManager.default.fileExists(atPath: url.path) else { return [] }
    do {
      let handle = try FileHandle(forReadingFrom: url)
      let data: Data?
      do { data = try handle.read(upToCount: Self.maximumBytes + 1) } catch {
        do { try handle.close() } catch {
          Self.log.caughtError("Could not close Siri summary", error)
        }
        throw error
      }
      try handle.close()
      guard let data, data.count <= Self.maximumBytes else { throw SiriMediaFailure.unavailable }
      return Array(try JSONDecoder().decode([Record].self, from: data).suffix(16))
    } catch {
      Self.log.caughtError("Could not read retained Siri resolution summary", error)
      return []
    }
  }
}
