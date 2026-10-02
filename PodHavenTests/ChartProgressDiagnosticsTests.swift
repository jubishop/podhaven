// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Logging
import Sentry
import SwiftUI
import Testing

@testable import PodHaven

@Suite("Chart diagnostic journal", .container)
@MainActor struct ChartProgressDiagnosticsTests {
  @Test("competing downloads cannot hide the final pre-render playback or download state")
  func competingInstances() throws {
    Container.shared.fakeContinuousClock().freeze()
    let instances = (0..<3).map { _ in ChartProgressInstance() }
    for revision in 1...200 {
      for index in instances.indices where index != 2 || revision.isMultiple(of: 20) {
        instances[index]
          .record(
            ChartProgressInput(
              source: index == 2 ? .playback : .download,
              total: 1,
              values: [Double(revision) / 1000],
              sectorKeys: [1],
              innerRadiusRatio: 0.4,
              angularInset: 2,
              numerator: Double(revision),
              denominator: 1000
            ),
            size: CGSize(width: index == 2 ? 28 : 12, height: index == 2 ? 28 : 12),
            scene: .active,
            phase: .render
          )
      }
    }
    let retained = try snapshots()
    let groups = Dictionary(grouping: retained) { $0["instance"] as? String }
    #expect(groups.count == 3)
    for rows in groups.values {
      let latest = try #require(
        rows.max { ($0["sequence"] as? Int ?? 0) < ($1["sequence"] as? Int ?? 0) }
      )
      let playback = latest["source"] as? String == "playback"
      #expect(latest["numerator"] as? Double == 200)
      #expect(latest["revision"] as? Int == (playback ? 10 : 200))
      #expect(latest["sequence"] as? Int == (playback ? 10 : 200))
      #expect(latest["width"] as? Double == (playback ? 28 : 12))
      #expect(latest["geometryObservation"] as? String == "current_render")
    }
  }

  @Test("non-finite and negative values are safe JSON with explicit classifications")
  func malformedValues() throws {
    let input = ChartProgressInput(
      source: .playback,
      total: .infinity,
      values: [.nan, .infinity, -.infinity, -1, 0, 0.000001],
      sectorKeys: [1, 2, 3, 4, 5, 6],
      innerRadiusRatio: 0.4,
      angularInset: 2,
      numerator: .nan,
      denominator: .infinity
    )
    let instance = ChartProgressInstance()
    instance.record(input, size: .zero, scene: .active, phase: .render)
    instance.record(input, size: .zero, scene: .active, phase: .render)
    let snapshots = try snapshots()
    #expect(snapshots.count == 1)
    let snapshot = try #require(snapshots.first)
    #expect(
      snapshot["values"] as? [AnyHashable] == ["NaN", "+Infinity", "-Infinity", -1, 0, 0.000001]
    )
    #expect(
      snapshot["valueClasses"] as? [String] == [
        "nan", "positiveInfinity", "negativeInfinity", "negative", "zero", "positive",
      ]
    )
    #expect(snapshot["totalClass"] as? String == "positiveInfinity")
    #expect(snapshot["proportions"] == nil)
    #expect(snapshot["width"] as? Double == 0)
    #expect(snapshot["numerator"] as? String == "NaN")
    #expect(snapshot["denominator"] as? String == "+Infinity")
  }

  @Test("input revisions distinguish shape changes, geometry, animation and lifecycle")
  func revisionsAndTransitions() throws {
    let instance = ChartProgressInstance()
    let input = ChartProgressInput(
      source: .opml,
      total: 3,
      values: [0, 1],
      sectorKeys: [10, 20],
      innerRadiusRatio: 0.5,
      angularInset: 2,
      waitingCount: 2
    )
    let inserted = ChartProgressInput(
      source: .opml,
      total: 3,
      values: [0, 1, 1],
      sectorKeys: [10, 20, 30],
      innerRadiusRatio: 0.5,
      angularInset: 2,
      waitingCount: 1
    )
    instance.record(input, size: CGSize(width: 12, height: 12), scene: .active, phase: .render)
    instance.record(input, size: CGSize(width: 12, height: 12), scene: .active, phase: .render)
    instance.record(input, size: CGSize(width: 28, height: 28), scene: .active, phase: .render)
    instance.record(
      inserted,
      scene: .active,
      phase: .transaction,
      transaction: SwiftUI.Transaction(animation: .default)
    )
    instance.record(input, scene: .active, phase: .render)
    instance.record(input, scene: .background, phase: .scene)
    instance.record(input, scene: .background, phase: .disappeared)
    let snapshots = try snapshots()
    #expect(snapshots.count == 6)
    #expect(snapshots.compactMap { $0["revision"] as? Int } == [1, 1, 2, 3, 3, 3])
    #expect(snapshots.compactMap { $0["sequence"] as? Int } == Array(1...6))
    #expect(Set(snapshots.compactMap { $0["instance"] as? String }).count == 1)
    #expect(snapshots[2]["sectorKeys"] as? [Int] == [10, 20, 30])
    #expect(snapshots[2]["animationPresent"] as? Bool == true)
    #expect(snapshots[2]["width"] as? Double == 28)
    #expect(snapshots[4]["scene"] as? String == "background")
    #expect(snapshots[5]["transition"] as? String == "disappeared")
    #expect(snapshots[0]["source"] as? String == "opml")
    #expect(snapshots[0]["waitingCount"] as? Int == 2)
    #expect(snapshots[0]["remainder"] as? Double == 2)
    #expect(snapshots[0]["remainderInserted"] as? Bool == true)
    #expect(snapshots[0]["proportions"] as? [Double] == [0, 1.0 / 3])
  }

  @Test(
    "complete and over-complete progress record actual Charts proportions",
    arguments: [1.0, 1.25]
  )
  func completeProgress(_ value: Double) throws {
    ChartProgressInstance()
      .record(
        ChartProgressInput(
          source: .playback,
          total: 1,
          values: [value],
          sectorKeys: [1],
          innerRadiusRatio: 0.4,
          angularInset: 2,
          numerator: value * 100,
          denominator: 100
        ),
        size: CGSize(width: 28, height: 28),
        scene: .active,
        phase: .render
      )
    let snapshot = try #require(try snapshots().first)
    #expect(snapshot["remainderInserted"] as? Bool == false)
    #expect(snapshot["remainder"] as? Double == 1 - value)
    #expect(snapshot["proportions"] as? [Double] == [1])
    #expect(snapshot["outOfRange"] as? [Bool] == [value > 1])
    #expect(snapshot["numerator"] as? Double == value * 100)
    #expect(snapshot["source"] as? String == "playback")
  }

  @Test("prior session survives current journal churn and outgoing Sentry envelope")
  func retentionAndDelivery() async throws {
    let priorID = UUID().uuidString
    let directory = ChartProgressDiagnostics.directory
    let prior = try ChartProgressStore(
      directory: directory,
      session: ChartProgressSession(
        sessionID: priorID,
        version: "prior-version",
        buildNumber: "prior-build",
        gitCommitHash: "prior-commit"
      )
    )
    prior.record(Self.snapshot(source: .playback, sequence: 1))
    let priorData = try prior.export(sessionID: priorID)
    let clock = Container.shared.fakeContinuousClock()
    clock.freeze()
    let instance = ChartProgressInstance()
    for index in 0..<300 {
      clock.advance(by: .seconds(2))
      instance.record(
        ChartProgressInput(
          source: .download,
          total: 1,
          values: [Double(index) / 300],
          sectorKeys: [1],
          innerRadiusRatio: 0.4,
          angularInset: 2,
          numerator: Double(index),
          denominator: 300
        ),
        scene: .active,
        phase: .render
      )
    }
    let data = try prior.export(sessionID: priorID)
    #expect(data == priorData)
    #expect(data.count <= ChartProgressDiagnostics.maximumBytes)
    let latest = try #require(try snapshots().last)
    #expect(latest["numerator"] as? Double == 299)
    #expect(latest["denominator"] as? Double == 300)
    #expect(latest["source"] as? String == "download")
    let options = Sentry.Options()
    AppLauncher.configureSentryOptions(options)
    let capture = try SentryEnvelopeCapture(options: options)
    let scope = Sentry.Scope()
    AppLauncher.configureInitialSentryScope(scope)
    let event = Sentry.Event(level: .fatal)
    event.tags = ["log-session-id": priorID]
    #expect(capture.client.capture(event: event, scope: scope) == event.eventId)
    let attachments = try await capture.items()
      .filter { $0.header["filename"] as? String == "chart-progress.ndjson" }
    #expect(attachments.count == 1)
    #expect(attachments.first?.data == data)
  }

  @Test("rapid updates retain latest history and attribute omitted transitions")
  func rapidUpdates() throws {
    Container.shared.fakeContinuousClock().freeze()
    let instance = ChartProgressInstance()
    for index in 0..<500 {
      instance.record(
        ChartProgressInput(
          source: .download,
          total: 1,
          values: [Double(index) / 500],
          sectorKeys: [1],
          innerRadiusRatio: 0.4,
          angularInset: 2
        ),
        scene: .active,
        phase: .render
      )
    }
    let data = try attachmentData()
    #expect(data.count <= ChartProgressDiagnostics.maximumBytes)
    #expect(try snapshots().count == ChartProgressStore.historyCapacity)
    let summary = try #require(try records().first)
    let instances = try #require(summary["instances"] as? [[String: Any]])
    #expect(
      instances.first?["omittedTransitions"] as? Int == 500 - ChartProgressStore.historyCapacity
    )
    #expect(instances.first?["latestSequence"] as? Int == 500)
    #expect(!String(decoding: data, as: UTF8.self).contains("deviceIdentifier"))
    #expect(!String(decoding: data, as: UTF8.self).contains("http"))
  }

  @Test("overflow prefers terminal instances and discloses bounded eviction attribution")
  func overflow() throws {
    let store = try ChartProgressStore(
      directory: ChartProgressDiagnostics.directory,
      session: Self.session()
    )
    let terminal = UUID()
    store.record(
      Self.snapshot(instance: terminal, source: .playback, sequence: 1, transition: "disappeared")
    )
    for _ in 1..<ChartProgressStore.instanceCapacity {
      store.record(Self.snapshot(source: .download, sequence: 1))
    }
    let before = try Self.rows(store.export(sessionID: FileLogHandler.sessionID))
    #expect(
      (before.first?["instances"] as? [[String: Any]])?
        .contains {
          $0["instance"] as? String == terminal.uuidString && $0["terminal"] as? Bool == true
        } == true
    )
    for _ in 0..<(ChartProgressStore.evictionCapacity + 2) {
      store.record(Self.snapshot(source: .opml, sequence: 1))
    }
    let data = try store.export(sessionID: FileLogHandler.sessionID)
    let summary = try #require(try Self.rows(data).first)
    #expect(summary["evictions"] as? Int == ChartProgressStore.evictionCapacity + 2)
    #expect(summary["omittedEvictionDetails"] as? Int == 2)
    #expect((summary["evictionsBySource"] as? [String: Int])?["playback"] == 1)
    #expect(
      (summary["instances"] as? [[String: Any]])?.count == ChartProgressStore.instanceCapacity
    )
    #expect(data.count <= ChartProgressDiagnostics.maximumBytes)
    let files = try FileManager.default.contentsOfDirectory(
      at: ChartProgressDiagnostics.directory,
      includingPropertiesForKeys: nil
    )
    #expect(
      try files.filter { $0.pathExtension == "bin" }.map { try Data(contentsOf: $0).count } == [
        ChartProgressStore.fileBytes
      ]
    )
  }

  @Test("session archives survive launch churn and report when capacity expires")
  func sessionIsolation() throws {
    let directory = ChartProgressDiagnostics.directory
    let incident = Self.session()
    let prior = try ChartProgressStore(directory: directory, session: incident)
    prior.record(Self.snapshot(source: .playback, sequence: 1))
    let expected = try prior.export(sessionID: incident.sessionID)
    for _ in 1..<ChartProgressStore.sessionCapacity {
      let store = try ChartProgressStore(
        directory: directory,
        session: Self.session(id: UUID().uuidString)
      )
      for sequence in 1...200 {
        store.record(Self.snapshot(instance: UUID(), source: .download, sequence: sequence))
      }
      #expect(try store.export(sessionID: incident.sessionID) == expected)
    }
    let next = try ChartProgressStore(
      directory: directory,
      session: Self.session(id: UUID().uuidString)
    )
    let missing = try Self.rows(next.export(sessionID: incident.sessionID))
    #expect(missing.first?["reason"] as? String == "session_not_retained")
    #expect(missing.first?["sessionID"] as? String == incident.sessionID)
    let files = try FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: nil
    )
    #expect(files.filter { $0.pathExtension == "bin" }.count == ChartProgressStore.sessionCapacity)
  }

  @Test("truncated sector payload retains actual sum and discloses full membership count")
  func sectorOverflow() throws {
    let input = ChartProgressInput(
      source: .opml,
      total: 20,
      values: Array(repeating: 1, count: 10),
      sectorKeys: Array(0..<10),
      innerRadiusRatio: 0.5,
      angularInset: 2
    )
    ChartProgressInstance()
      .record(input, size: CGSize(width: 28, height: 28), scene: .active, phase: .render)
    let snapshot = try #require(try snapshots().first)
    #expect(snapshot["sectorCount"] as? Int == 10)
    #expect((snapshot["values"] as? [Double])?.count == 8)
    #expect(snapshot["sum"] as? Double == 10)
    #expect(snapshot["remainder"] as? Double == 10)
    #expect(snapshot["proportions"] as? [Double] == Array(repeating: 0.05, count: 8))
  }

  @Test("transaction state is followed by measured pre-render state for the same input")
  func transactionThenRender() throws {
    let instance = ChartProgressInstance()
    let input = ChartProgressInput(
      source: .playback,
      total: 1,
      values: [0.000001],
      sectorKeys: [1],
      innerRadiusRatio: 0.4,
      angularInset: 2
    )
    let size = CGSize(width: 12, height: 12)
    instance.record(input, size: size, scene: .active, phase: .render)
    instance.record(
      input,
      scene: .active,
      phase: .transaction,
      transaction: SwiftUI.Transaction(animation: .default)
    )
    instance.record(input, size: size, scene: .active, phase: .render)
    let rows = try snapshots()
    #expect(rows.count == 3)
    #expect(rows[1]["geometryObservation"] as? String == "last_render")
    #expect(rows[2]["geometryObservation"] as? String == "current_render")
    #expect(rows[2]["revision"] as? Int == 1)
    #expect(rows[2]["animationPresent"] as? Bool == true)
  }

  @Test("a crash from the previous app version keeps its existing sampled journal")
  func legacySession() throws {
    let priorID = UUID().uuidString
    let url = AppInfo.recentLogFileURL.deletingLastPathComponent()
      .appendingPathComponent("chart-progress.ndjson")
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let prior =
      try JSONSerialization.data(withJSONObject: [
        "sessionID": priorID, "timestamp": 1,
        "metadata": ["chart": "{\"source\":\"playback\",\"sequence\":7}"],
      ]) + Data([0x0A])
    let unrelated =
      try JSONSerialization.data(withJSONObject: ["sessionID": UUID().uuidString]) + Data([0x0A])
    try (prior + unrelated).write(to: url)
    let attachment = Container.shared.chartProgressDiagnostics().attachment(sessionID: priorID)
    #expect(attachment.data == prior)
  }

  @Test("incomplete mapped records are disclosed with preceding state retained")
  func incompleteRecord() throws {
    let session = Self.session()
    let store = try ChartProgressStore(
      directory: ChartProgressDiagnostics.directory,
      session: session
    )
    let id = UUID()
    store.record(Self.snapshot(instance: id, source: .playback, sequence: 1))
    store.record(Self.snapshot(instance: id, source: .playback, sequence: 2))
    let url = ChartProgressDiagnostics.directory.appendingPathComponent(session.sessionID + ".bin")
    let handle = try FileHandle(forWritingTo: url)
    try handle.seek(
      toOffset: UInt64(ChartProgressStore.headerBytes + ChartProgressStore.recordBytes + 504)
    )
    try handle.write(contentsOf: Data(repeating: 0, count: 8))
    try handle.close()
    let rows = try Self.rows(store.export(sessionID: session.sessionID))
    #expect(rows.first?["invalidRecords"] as? Int == 1)
    #expect(rows.first?["invalidRecordSlots"] as? [Int] == [1])
    #expect((rows.first?["instances"] as? [[String: Any]])?.first?["latestSequence"] as? Int == 1)
  }

  @Test("full store exports all bounded states within attachment capacity")
  func maximumPayload() throws {
    let session = Self.session()
    let store = try ChartProgressStore(
      directory: ChartProgressDiagnostics.directory,
      session: session
    )
    for _ in 0..<ChartProgressStore.instanceCapacity {
      let id = UUID()
      for sequence in 1...ChartProgressStore.historyCapacity {
        store.record(
          ChartProgressSnapshot(
            input: ChartProgressInput(
              source: .opml,
              total: 1,
              values: Array(repeating: .greatestFiniteMagnitude, count: 8),
              sectorKeys: Array(repeating: Int.min, count: 8),
              innerRadiusRatio: 0.5,
              angularInset: 2
            ),
            instance: id,
            revision: sequence,
            sequence: sequence,
            transition: "render",
            size: CGSize(width: 28, height: 28),
            scene: "active",
            animationPresent: true,
            animationsDisabled: false
          )
        )
      }
    }
    let data = try store.export(sessionID: session.sessionID)
    #expect(data.count <= ChartProgressDiagnostics.maximumBytes)
    #expect(
      try Self.rows(data).count == 1 + ChartProgressStore.instanceCapacity
        * ChartProgressStore.historyCapacity
    )
  }

  @Test("measure pre-render capture and export cost against the former synchronous journal")
  func captureCost() throws {
    let instances = (0..<3).map { _ in ChartProgressInstance() }
    let legacyURL = ChartProgressDiagnostics.directory.appendingPathComponent("benchmark.ndjson")
    let diagnostics = Container.shared.chartProgressDiagnostics()
    let legacy = FileLogHandler(
      label: "PodHaven/ChartBenchmark",
      fileURL: legacyURL,
      maxFileSizeBytes: 64 * 1024,
      targetFileSizeBytes: 48 * 1024,
      writeSynchronously: { _ in true }
    )
    let encoder = JSONEncoder()
    let legacyID = UUID()
    let clock = ContinuousClock()
    var mapped: [Double] = []
    var journal: [Double] = []
    for index in 1...3000 {
      let input = ChartProgressInput(
        source: index.isMultiple(of: 3) ? .playback : .download,
        total: 1,
        values: [Double(index) / 10000],
        sectorKeys: [1],
        innerRadiusRatio: 0.4,
        angularInset: 2
      )
      let capture = clock.measure {
        instances[index % 3]
          .record(input, size: CGSize(width: 12, height: 12), scene: .active, phase: .render)
      }
      mapped.append(Self.microseconds(capture))
      let old = try clock.measure {
        let snapshot = ChartProgressSnapshot(
          input: input,
          instance: legacyID,
          revision: index,
          sequence: index,
          transition: "render",
          size: CGSize(width: 12, height: 12),
          scene: "active",
          animationPresent: false,
          animationsDisabled: false
        )
        let data = try encoder.encode(snapshot)
        legacy.log(
          event: LogEvent(
            level: .debug,
            message: "chart transition",
            metadata: ["chart": .string(String(decoding: data, as: UTF8.self))],
            source: "ChartBenchmark",
            file: #fileID,
            function: #function,
            line: #line
          )
        )
      }
      journal.append(Self.microseconds(old))
    }
    let export = clock.measure { _ = diagnostics.attachment(sessionID: FileLogHandler.sessionID) }
    mapped.sort()
    journal.sort()
    print(
      "CHART_COST samples=3000 mapped_p50_us=\(mapped[1500]) mapped_p95_us=\(mapped[2850]) legacy_p50_us=\(journal[1500]) legacy_p95_us=\(journal[2850]) export_us=\(Self.microseconds(export)) mapped_bytes=\(ChartProgressStore.fileBytes)"
    )
    #expect(try snapshots().count == 3 * ChartProgressStore.historyCapacity)
  }

  private static func microseconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1_000_000 + Double(duration.components.attoseconds)
      / 1_000_000_000_000
  }

  private static func session(id: String = FileLogHandler.sessionID) -> ChartProgressSession {
    ChartProgressSession(
      sessionID: id,
      version: "test",
      buildNumber: "1",
      gitCommitHash: "synthetic"
    )
  }

  private static func snapshot(
    instance: UUID = UUID(),
    source: ChartProgressInput.Source,
    sequence: Int,
    transition: String = "render"
  ) -> ChartProgressSnapshot {
    ChartProgressSnapshot(
      input: ChartProgressInput(
        source: source,
        total: 1,
        values: [0.000001],
        sectorKeys: [1],
        innerRadiusRatio: 0.4,
        angularInset: 2
      ),
      instance: instance,
      revision: sequence,
      sequence: sequence,
      transition: transition,
      size: CGSize(width: 12, height: 12),
      scene: "active",
      animationPresent: nil,
      animationsDisabled: nil
    )
  }

  private static func rows(_ data: Data) throws -> [[String: Any]] {
    try data.split(separator: 0x0A)
      .map {
        try #require(JSONSerialization.jsonObject(with: Data($0)) as? [String: Any])
      }
  }

  private func attachmentData() throws -> Data {
    try #require(
      Container.shared.chartProgressDiagnostics().attachment(sessionID: FileLogHandler.sessionID)
        .data
    )
  }

  private func records() throws -> [[String: Any]] {
    try Self.rows(attachmentData())
  }

  private func snapshots() throws -> [[String: Any]] {
    try records()
      .compactMap { record in
        guard let metadata = record["metadata"] as? [String: String], let json = metadata["chart"]
        else { return nil }
        return try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
      }
  }
}
