// Copyright Justin Bishop, 2026

import FactoryTesting
import Foundation
import Intents
import Testing

@testable import PodHaven

@Suite("of Siri callback responsiveness", .container)
struct SiriResponsivenessTests {
  @Test(
    "system callbacks return before catalog work and never read on the main thread",
    arguments: ["resolve", "confirm", "handle"]
  )
  @MainActor func callbackBoundary(mode: String) async throws {
    let url = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let catalog = SiriCatalog(entries: [
      .init(
        identity: .init(kind: .podcast, id: 1, feed: "https://synthetic.test"),
        title: "Synthetic show",
        podcastTitle: nil
      )
    ])
    try SiriCatalogFile(url: url).write(catalog)
    let opened = ThreadSafe(false)
    let release = AsyncStream<Void>.makeStream()
    defer { release.continuation.finish() }
    let file = SiriCatalogFile(
      url: url,
      openForReading: { url in
        opened(true)
        for await _ in release.stream { break }
        #expect(
          !{ Thread.isMainThread }(),
          "Catalog I/O must leave the main-thread system callback"
        )
        return try FileHandle(forReadingFrom: url)
      }
    )
    let handler = SiriMediaIntentHandler(catalog: file.read, authorized: { true })
    let callbacks = ThreadSafe(0)
    let intent = SiriTestIntent.named("Synthetic show")
    switch mode {
    case "resolve": handler.resolveMediaItems(for: intent) { _ in callbacks { $0 += 1 } }
    case "confirm": handler.confirm(intent: intent) { _ in callbacks { $0 += 1 } }
    default: handler.handle(intent: intent) { _ in callbacks { $0 += 1 } }
    }
    #expect(callbacks() == 0, "The main actor must regain control before catalog completion")
    try await Wait.until({ opened() }, { "Catalog file open did not start" })
    MainActor.preconditionIsolated()
    #expect(callbacks() == 0, "Main-actor work progresses while the file operation is pending")
    release.continuation.yield(())
    try await Wait.until({ callbacks() == 1 }, { "Siri callback did not complete" })
    #expect(callbacks() == 1)
  }
  @Test("a newer handle request supersedes catalog work and completes each callback once")
  @MainActor func supersededCatalog() async throws {
    let url = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let count = ThreadSafe(0)
    let opened = ThreadSafe(false)
    let release = AsyncStream<Void>.makeStream()
    defer { release.continuation.finish() }
    let file = SiriCatalogFile(
      url: url,
      openForReading: { url in
        let first = count { count in
          count += 1
          return count == 1
        }
        if first {
          opened(true)
          for await _ in release.stream { break }
        }
        return try FileHandle(forReadingFrom: url)
      }
    )
    try file.write(
      SiriCatalog(entries: [
        .init(
          identity: .init(kind: .podcast, id: 1, feed: "https://synthetic.test"),
          title: "Synthetic show",
          podcastTitle: nil
        )
      ])
    )
    let handler = SiriMediaIntentHandler(catalog: file.read, authorized: { true })
    let responses = ThreadSafe<[String: [Int]]>([:])
    handler.handle(intent: SiriTestIntent.named("Synthetic show")) { response in
      responses { $0["first", default: []].append(response.code.rawValue) }
    }
    try await Wait.until({ opened() }, { "First catalog open did not start" })
    handler.handle(intent: SiriTestIntent.named("Synthetic show")) { response in
      responses { $0["second", default: []].append(response.code.rawValue) }
    }
    try await Wait.until(
      { responses()["second"] != nil },
      { "Newer catalog request did not complete" }
    )
    release.continuation.yield(())
    try await Wait.until(
      { responses().values.reduce(0) { $0 + $1.count } == 2 },
      { "Missing overlapping catalog callbacks" }
    )
    #expect(responses()["first"] == [INPlayMediaIntentResponseCode.failure.rawValue])
    #expect(responses()["second"] == [INPlayMediaIntentResponseCode.handleInApp.rawValue])
  }
}
