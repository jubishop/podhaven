// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Intents
import Sentry
import Testing

@testable import PodHaven

@Suite("of retained Siri resolution diagnostics", .container)
struct SiriResolutionDiagnosticsTests {
  @Test("slow successes and failures have independent bounded uploads", arguments: [false, true])
  func independentFailureCapture(deferred: Bool) async throws {
    let file = Container.shared.siriCatalogFile()
    defer { try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent()) }
    let journal = SiriResolutionJournal(
      url: file.url.deletingLastPathComponent()
        .appendingPathComponent("siri-extension-resolutions.json"),
      sessionID: "extension-session",
      version: "1",
      build: "extension-build",
      commit: "extension-commit",
      process: "extension"
    )
    let outcomes = ThreadSafe<[String]>([])
    Container.shared.siriDiagnosticCapture.context(.test) {
      { event in outcomes { $0.append(event.tags?["siri-outcome"] ?? "missing") } }
    }
    let diagnostics = Container.shared.siriResolutionDiagnostics()
    for outcome in ["unique", "failed", "ambiguous", "noMatch"] {
      var summary = SiriResolutionOperation.Summary(
        operationID: UUID(),
        startedAt: Date(),
        mode: "resolve",
        requestMode: "name",
        mediaType: INMediaItemType.unknown.rawValue,
        callbackMainThread: false
      )
      summary.phase = .finished
      summary.totalMs = 1_500
      summary.outcome = outcome
      if deferred { journal.record(summary) } else { diagnostics.record(summary) }
    }
    if deferred { await diagnostics.captureExtensionFailures() }
    #expect(outcomes() == ["unique", "failed"])
  }

  @Test("journal time remains in total duration but outside catalog phase durations")
  func phaseTimingExcludesJournal() throws {
    let url = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let journal = SiriResolutionJournal(
      url: url,
      sessionID: "test",
      version: "1",
      build: "1",
      commit: "test",
      process: "app"
    )
    let reportingMs = ThreadSafe(0.0)
    let operation = SiriResolutionOperation(
      mode: "resolve",
      intent: SiriTestIntent.named("Synthetic show"),
      report: { summary in
        let started = ProcessInfo.processInfo.systemUptime
        journal.record(summary)
        if summary.phase != .finished {
          reportingMs { $0 += (ProcessInfo.processInfo.systemUptime - started) * 1_000 }
        }
      }
    )
    operation.begin(.read)
    operation.begin(.decode)
    operation.begin(.match)
    operation.finish(outcome: "unique")
    let summary = try #require(journal.read().last?.summary)
    let catalogMs = summary.readMs + summary.decodeMs + summary.matchMs
    #expect(reportingMs() > 0)
    #expect(summary.totalMs - catalogMs >= reportingMs())
  }

  @Test("failed real resolution sends bounded attributed summaries without private metadata")
  @MainActor func failureEnvelope() async throws {
    let file = Container.shared.siriCatalogFile()
    defer { try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent()) }
    try file.write(
      SiriCatalog(entries: [
        .init(
          identity: .init(
            kind: .episode,
            id: 735931,
            feed: "https://private.invalid/feed",
            guid: "private-guid"
          ),
          title: "Private title",
          podcastTitle: "Private album"
        )
      ])
    )
    let captured = ThreadSafe<[Data]>([])
    Container.shared.siriDiagnosticCapture.context(.test) {
      { event in
        do {
          let data = try JSONSerialization.data(withJSONObject: [
            "tags": event.tags ?? [:], "context": event.context ?? [:],
          ])
          captured { $0.append(data) }
        } catch { Issue.record(error) }
      }
    }
    let handler = SiriMediaIntentHandler(
      catalog: file.read,
      authorized: { true },
      diagnostic: { Container.shared.siriResolutionDiagnostics().record($0) }
    )
    await withCheckedContinuation { continuation in
      handler.resolveMediaItems(for: SiriTestIntent.named("Private missing query")) { _ in
        continuation.resume()
      }
    }
    let eventData = try #require(captured().first)
    let attachment = try #require(Container.shared.siriResolutionDiagnostics().attachments().first)
    let data = try #require(attachment.data)
    #expect(data.count <= SiriResolutionJournal.maximumBytes)
    let records = try JSONDecoder().decode([SiriResolutionJournal.Record].self, from: data)
    let record = try #require(records.last)
    #expect(record.sessionID == FileLogHandler.sessionID)
    #expect(record.commit == AppInfo.gitCommitHash)
    #expect(record.build == AppInfo.buildNumber)
    #expect(record.summary.phase == .finished)
    #expect(record.summary.outcome == "noMatch")
    #expect(record.summary.callbackMainThread)
    #expect(!record.summary.workerMainThread)
    #expect(record.summary.entries == 1)
    #expect(record.summary.bytes > 0)
    #expect(record.summary.maxTitleBytes == "Private album".utf8.count)
    #expect(record.summary.readMs > 0 && record.summary.decodeMs > 0 && record.summary.matchMs > 0)
    let json = String(decoding: eventData + data, as: UTF8.self)
    for privateValue in [
      "Private title", "Private album", "Private missing query", "private.invalid", "private-guid",
      "735931",
    ] {
      #expect(!json.contains(privateValue))
    }
    #expect(json.contains(record.summary.operationID.uuidString))
  }

  @Test(
    "journal retains bounded summaries across restart and corrupt or oversized files fail closed"
  )
  func boundedHistory() throws {
    let url = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let make = {
      SiriResolutionJournal(
        url: url,
        sessionID: "original-session",
        version: "1",
        build: "579",
        commit: "original-commit",
        process: "app"
      )
    }
    let journal = make()
    for _ in 0..<40 {
      let operation = SiriResolutionOperation(
        mode: "resolve",
        intent: SiriTestIntent.named("private"),
        report: journal.record
      )
      operation.begin(.read)
      operation.finish(outcome: "failed")
    }
    let records = make().read()
    #expect(records.count == 16)
    #expect(
      records.allSatisfy { $0.sessionID == "original-session" && $0.commit == "original-commit" }
    )
    #expect(try Data(contentsOf: url).count <= SiriResolutionJournal.maximumBytes)
    try Data(repeating: 32, count: SiriResolutionJournal.maximumBytes + 1).write(to: url)
    #expect(make().read().isEmpty)
    try Data("invalid JSON".utf8).write(to: url)
    #expect(make().read().isEmpty)
  }

  @Test(
    "recovered and delayed fatal hang envelopes keep original operation attribution",
    arguments: ["App Hang Fully Blocked", "Fatal App Hang Fully Blocked"]
  )
  func hangEnvelope(type: String) async throws {
    let file = Container.shared.siriCatalogFile()
    defer { try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent()) }
    let journal = SiriResolutionJournal(
      url: file.url.deletingLastPathComponent().appendingPathComponent("siri-app-resolutions.json"),
      sessionID: "previous-session",
      version: "1",
      build: "prior-build",
      commit: "prior-commit",
      process: "app"
    )
    let operation = SiriResolutionOperation(
      mode: "resolve",
      intent: SiriTestIntent.named("Private query"),
      report: journal.record
    )
    operation.begin(.read)
    let options = Sentry.Options()
    AppLauncher.configureSentryOptions(options)
    let transport = try SentryEnvelopeCapture(options: options)
    let event = Sentry.Event(level: .error)
    let exception = Exception(value: "Controlled hang", type: type)
    exception.mechanism = Mechanism(type: "AppHang")
    event.exceptions = [exception]
    _ = transport.client.capture(event: event, scope: Scope())
    let items = try await transport.items()
    let attachment = try #require(
      items.first { $0.header["filename"] as? String == "siri-app-resolutions.json" }
    )
    let records = try JSONDecoder()
      .decode([SiriResolutionJournal.Record].self, from: attachment.data)
    #expect(records.count == 1)
    #expect(records[0].sessionID == "previous-session")
    #expect(records[0].build == "prior-build")
    #expect(records[0].summary.phase == .read)
    #expect(records[0].summary.outcome == "pending")
  }
  @Test("extension failures retain origin attribution and are not recaptured after app restart")
  func extensionFailure() async throws {
    let file = Container.shared.siriCatalogFile()
    defer { try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent()) }
    let journal = SiriResolutionJournal(
      url: file.url.deletingLastPathComponent()
        .appendingPathComponent("siri-extension-resolutions.json"),
      sessionID: "extension-session",
      version: "1",
      build: "extension-build",
      commit: "extension-commit",
      process: "extension"
    )
    let operation = SiriResolutionOperation(
      mode: "resolve",
      intent: SiriTestIntent.named("Private query"),
      report: journal.record
    )
    operation.finish(outcome: "failed")
    let captures = ThreadSafe<[Data]>([])
    Container.shared.siriDiagnosticCapture.context(.test) {
      { event in
        do {
          let data = try JSONSerialization.data(withJSONObject: event.context ?? [:])
          captures { $0.append(data) }
        } catch { Issue.record(error) }
      }
    }
    await Container.shared.siriResolutionDiagnostics().captureExtensionFailures()
    Container.shared.siriResolutionDiagnostics.reset(.scope)
    await Container.shared.siriResolutionDiagnostics().captureExtensionFailures()
    #expect(captures().count == 1)
    let data = try #require(captures().first)
    let json = String(decoding: data, as: UTF8.self)
    #expect(json.contains("extension-session"))
    #expect(json.contains("extension-build"))
    #expect(json.contains("extension-commit"))
    #expect(json.contains("deferred_extension_upload"))
    #expect(!json.contains("Private query"))
  }

}
