// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Intents
import Testing

@testable import PodHaven

@Suite("of Siri media catalogs", .container)
struct SiriCatalogTests {
  private func entry(_ id: Int64, _ title: String, kind: SiriMediaIdentity.Kind = .episode)
    -> SiriCatalog.Entry
  {
    SiriCatalog.Entry(
      identity: SiriMediaIdentity(
        kind: kind,
        id: id,
        feed: "https://podcast.test/\(id)",
        guid: "\(id)"
      ),
      title: title,
      podcastTitle: kind == .episode ? "A show" : nil
    )
  }

  @Test("normalized exact names outrank broader matches, with stable ambiguous choices")
  func ranking() throws {
    let exact = entry(3, "Café — Science")
    let duplicate = entry(1, "CAFE Science")
    let catalog = SiriCatalog(entries: [entry(2, "Café Science Today"), exact, duplicate])
    #expect(
      try catalog.matches(SiriTestIntent.named("  cafe SCIENCE! ")).map(\.identity.id) == [1, 3]
    )
    #expect(try catalog.matches(SiriTestIntent.named("Science Today")).map(\.identity.id) == [2])
    #expect(
      try catalog.matches(SiriTestIntent.named("Café Science Today")) == [
        entry(2, "Café Science Today")
      ]
    )
  }

  @Test("podcast and episode requests remain distinct")
  func mediaType() throws {
    let show = entry(1, "A title", kind: .podcast)
    let episode = entry(2, "A title")
    let catalog = SiriCatalog(entries: [show, episode])
    #expect(try catalog.matches(SiriTestIntent.named("A title", type: .podcastShow)) == [show])
    #expect(
      try catalog.matches(SiriTestIntent.named("A title", type: .podcastEpisode)) == [episode]
    )
    #expect(try catalog.matches(SiriTestIntent.named("A title")).count == 2)
  }

  @Test("unsupported options and missing names fail without guessing")
  func unsupported() {
    let catalog = SiriCatalog(entries: [entry(1, "One")])
    #expect(throws: (any Error).self) { try catalog.matches(SiriTestIntent.named(nil)) }
    #expect(throws: (any Error).self) { try catalog.matches(SiriTestIntent.named("Other")) }
    #expect(throws: (any Error).self) {
      try catalog.matches(SiriTestIntent.named("One", type: .song))
    }
    #expect(throws: (any Error).self) {
      try catalog.matches(SiriTestIntent.named("One", shuffled: true))
    }
  }

  @Test("resolved identities survive encoding and reject deletion, reuse, and renamed titles")
  func identity() throws {
    let original = entry(1, "Original")
    let encoded = try JSONEncoder().encode(SiriCatalog(entries: [original]))
    let catalog = try JSONDecoder().decode(SiriCatalog.self, from: encoded)
    let intent = try SiriTestIntent.resolved(original)
    #expect(try catalog.matches(intent) == [original])
    #expect(throws: (any Error).self) { try SiriCatalog(entries: []).matches(intent) }
    #expect(throws: (any Error).self) {
      try SiriCatalog(entries: [entry(1, "Renamed")]).matches(intent)
    }
    let replaced = SiriCatalog.Entry(
      identity: SiriMediaIdentity(kind: .episode, id: 1, feed: "https://other.test", guid: "other"),
      title: "Original",
      podcastTitle: "A show"
    )
    #expect(throws: (any Error).self) { try SiriCatalog(entries: [replaced]).matches(intent) }
  }

  @Test(
    "background database commits publish inserts, renames, deletion, and rollback synchronously"
  )
  func databaseFreshness() async throws {
    let db = Container.shared.appDB()
    let file = Container.shared.siriCatalogFile()
    defer { try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent()) }
    db.startSiriCatalog(file)
    #expect(try file.read().entries.isEmpty)
    let series = try await Container.shared.repo()
      .insertSeries(
        UnsavedPodcastSeries(
          unsavedPodcast: try Create.unsavedPodcast(title: "Show"),
          unsavedEpisodes: [try Create.unsavedEpisode(title: "Episode")]
        )
      )
    #expect(try file.read().entries.map(\.title) == ["Show", "Episode"])
    try await db.writer.write { db in
      try Podcast.withID(series.podcast.id).updateAll(db, Podcast.Columns.title.set(to: "New show"))
    }
    #expect(try file.read().entries.map(\.displayTitle) == ["New show", "Episode — New show"])
    do {
      try await db.writer.write { db in
        try Podcast.withID(series.podcast.id).deleteAll(db)
        throw URLError(.cancelled)
      }
    } catch {}
    #expect(try file.read().entries.count == 2)
    try await Container.shared.repo().deletePodcast(series.podcast.id)
    #expect(try file.read().entries.isEmpty)
  }

  @Test("catalog publication does not read transcript or description payloads")
  func narrowPublication() async throws {
    let series = try await Container.shared.repo()
      .insertSeries(
        UnsavedPodcastSeries(
          unsavedPodcast: try Create.unsavedPodcast(title: "Named show"),
          unsavedEpisodes: [try Create.unsavedEpisode(title: "Named episode")]
        )
      )
    let episode = PodcastEpisode(podcast: series.podcast, episode: series.episodes[0])
    let file = Container.shared.siriCatalogFile()
    defer { try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent()) }
    try await Container.shared.appDB().writer
      .write { db in
        let queries = ThreadSafe<[String]>([])
        db.trace { event in
          if case .statement(let statement) = event {
            queries { $0.append(statement.sql) }
          }
        }
        SiriCatalogPublisher(file: file).publish(db)
        db.trace(options: [])
        #expect(!queries().isEmpty)
        for query in queries() {
          let region = try db.makeStatement(sql: query).databaseRegion
          for (table, column) in [
            ("episode", "transcript"), ("episode", "description"), ("podcast", "description"),
          ] {
            #expect(
              !region.isModified(byEventsOfKind: .update(tableName: table, columnNames: [column])),
              "Catalog publication must not read \(table).\(column)"
            )
          }
        }
      }
    let entries = try file.read().entries
    #expect(entries.count == 2)
    #expect(entries[0].identity.id == episode.podcast.id.rawValue)
    #expect(entries[0].title == episode.podcastTitle)
    #expect(entries[1].identity.id == episode.id.rawValue)
    #expect(entries[1].identity.feed == episode.feedURL.absoluteString)
    #expect(entries[1].identity.guid == episode.episode.guid.rawValue)
    #expect(entries[1].displayTitle == "Named episode — \(episode.podcastTitle)")
  }

  @Test("unavailable or invalidated catalog data never produces a handoff")
  func unavailableCatalog() throws {
    let file = Container.shared.siriCatalogFile()
    defer { try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent()) }
    let handler = SiriMediaIntentHandler(catalog: file.read, authorized: { true })
    let responses = ThreadSafe<[Int]>([])
    handler.handle(intent: SiriTestIntent.named("One")) { code in
      responses { $0.append(code.code.rawValue) }
    }
    try file.write(SiriCatalog(entries: [entry(1, "One")]))
    try file.invalidate()
    handler.handle(intent: SiriTestIntent.named("One")) { code in
      responses { $0.append(code.code.rawValue) }
    }
    #expect(
      responses() == Array(repeating: INPlayMediaIntentResponseCode.failure.rawValue, count: 2)
    )
  }

  @Test("extension confirms a unique request and hands audio to the app exactly once")
  func extensionHandoff() throws {
    let catalog = SiriCatalog(entries: [entry(1, "One")])
    let handler = SiriMediaIntentHandler(catalog: { catalog }, authorized: { true })
    let responses = ThreadSafe<[Int]>([])
    handler.confirm(intent: SiriTestIntent.named("One")) { code in
      responses { $0.append(code.code.rawValue) }
    }
    handler.handle(intent: try SiriTestIntent.resolved(catalog.entries[0])) { code in
      responses { $0.append(code.code.rawValue) }
    }
    #expect(
      responses() == [
        INPlayMediaIntentResponseCode.ready.rawValue,
        INPlayMediaIntentResponseCode.handleInApp.rawValue,
      ]
    )
    let denied = SiriMediaIntentHandler(catalog: { catalog }, authorized: { false })
    denied.handle(intent: SiriTestIntent.named("One")) { code in
      responses { $0.append(code.code.rawValue) }
    }
    #expect(responses().last == INPlayMediaIntentResponseCode.failure.rawValue)
  }
}
