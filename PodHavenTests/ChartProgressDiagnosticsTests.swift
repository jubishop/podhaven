// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Sentry
import SwiftUI
import Testing

@testable import PodHaven

@Suite("Chart diagnostic journal", .container)
@MainActor struct ChartProgressDiagnosticsTests {
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
    let url = ChartProgressDiagnostics.fileURL
    let priorID = UUID().uuidString
    let prior =
      try JSONSerialization.data(withJSONObject: [
        "sessionID": priorID, "buildNumber": "prior-build", "gitCommitHash": "prior-commit",
        "version": "prior-version", "timestamp": 123, "message": "chart transition",
        "metadata": ["chart": "{\"source\":\"playback\",\"values\":[0.001]}"],
      ]) + Data([0x0A])
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try prior.write(to: url)
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
    let data = try Data(contentsOf: url)
    #expect(data.count <= ChartProgressDiagnostics.maximumBytes)
    #expect(data.starts(with: prior))
    let records = try records()
    #expect(records.first?["sessionID"] as? String == priorID)
    #expect(records.last?["sessionID"] as? String == FileLogHandler.sessionID)
    #expect(records.last?["gitCommitHash"] as? String == AppInfo.gitCommitHash)
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

  @Test("rapid updates stay bounded and disclose dropped snapshots")
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
    FileLogHandler.flush(fileURL: ChartProgressDiagnostics.fileURL)
    let data = try Data(contentsOf: ChartProgressDiagnostics.fileURL)
    #expect(data.count <= ChartProgressDiagnostics.maximumBytes)
    #expect(try snapshots().count <= 50)
    #expect(String(decoding: data, as: UTF8.self).contains("450"))
    let records = try records()
    let permitted: Set<String> = [
      "level", "levelName", "timestamp", "subsystem", "category", "message", "metadata", "source",
      "file", "function", "line", "sessionID", "version", "buildNumber", "gitCommitHash",
    ]
    #expect(records.allSatisfy { Set($0.keys).isSubset(of: permitted) })
  }

  private func records() throws -> [[String: Any]] {
    try String(contentsOf: ChartProgressDiagnostics.fileURL, encoding: .utf8)
      .split(separator: "\n")
      .map {
        try #require(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
      }
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
