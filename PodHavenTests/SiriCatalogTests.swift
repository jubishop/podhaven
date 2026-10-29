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
  private func podcast(
    _ id: Int64 = 0,
    _ title: String = "A show",
    episodes: [(Int64, String)] = []
  ) -> SiriCatalog.Podcast {
    SiriCatalog.Podcast(
      id: id,
      feed: "https://podcast.test/\(id)",
      title: title,
      episodes: episodes.map { SiriCatalog.Episode(id: $0.0, guid: "\($0.0)", title: $0.1) }
    )
  }

  @Test("normalized exact names outrank broader matches, with stable ambiguous choices")
  func ranking() throws {
    let show = podcast(episodes: [
      (2, "Café Science Today"), (3, "Café — Science"), (1, "CAFE Science"),
    ])
    let catalog = SiriCatalog(podcasts: [show])
    #expect(
      try catalog.matches(SiriTestIntent.named("  cafe SCIENCE! ")).map(\.identity.id) == [1, 3]
    )
    #expect(try catalog.matches(SiriTestIntent.named("Science Today")).map(\.identity.id) == [2])
    #expect(
      try catalog.matches(SiriTestIntent.named("Café Science Today")) == [
        show.entry(for: show.episodes[0])
      ]
    )
  }

  @Test("podcast and episode requests remain distinct")
  func mediaType() throws {
    let show = podcast(1, "A title", episodes: [(2, "A title")])
    let catalog = SiriCatalog(podcasts: [show])
    #expect(
      try catalog.matches(SiriTestIntent.named("A title", type: .podcastShow)) == [show.entry]
    )
    #expect(
      try catalog.matches(SiriTestIntent.named("A title", type: .podcastEpisode)) == [
        show.entry(for: show.episodes[0])
      ]
    )
    #expect(try catalog.matches(SiriTestIntent.named("A title")).count == 2)
  }

  @Test("album names select only episodes of the named podcast")
  func album() throws {
    let science = podcast(1, "Science Hour", episodes: [(3, "Weekly news")])
    let politics = podcast(2, "Politics Hour", episodes: [(4, "Weekly news")])
    let catalog = SiriCatalog(podcasts: [science, politics])
    #expect(
      try catalog.matches(SiriTestIntent.named("Weekly news", album: "politics hour")) == [
        politics.entry(for: politics.episodes[0])
      ]
    )
    #expect(throws: SiriMediaFailure.noMatch) {
      try catalog.matches(SiriTestIntent.named("Politics Hour", album: "Politics Hour"))
    }
    #expect(throws: SiriMediaFailure.noMatch) {
      try catalog.matches(SiriTestIntent.named("Weekly news", album: "Sports Hour"))
    }
  }

  @Test("unsupported options and missing names fail without guessing")
  func unsupported() {
    let catalog = SiriCatalog(podcasts: [podcast(episodes: [(1, "One")])])
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
    let show = podcast(episodes: [(1, "Original")])
    let original = show.entry(for: show.episodes[0])
    let encoded = try JSONEncoder().encode(SiriCatalog(podcasts: [show]))
    let catalog = try JSONDecoder().decode(SiriCatalog.self, from: encoded)
    let intent = try SiriTestIntent.resolved(original)
    #expect(try catalog.matches(intent) == [original])
    #expect(try catalog.matches(SiriTestIntent.resolved(show.entry)) == [show.entry])
    #expect(throws: (any Error).self) { try SiriCatalog(podcasts: []).matches(intent) }
    #expect(throws: (any Error).self) {
      try SiriCatalog(podcasts: [podcast(episodes: [(1, "Renamed")])]).matches(intent)
    }
    for (feed, guid) in [("https://other.test", "1"), (show.feed, "other")] {
      let replaced = SiriCatalog.Podcast(
        id: show.id,
        feed: feed,
        title: show.title,
        episodes: [SiriCatalog.Episode(id: 1, guid: guid, title: "Original")]
      )
      #expect(throws: (any Error).self) { try SiriCatalog(podcasts: [replaced]).matches(intent) }
    }
  }

  @Test(
    "background database commits publish inserts, renames, deletion, and rollback synchronously"
  )
  func databaseFreshness() async throws {
    let db = Container.shared.appDB()
    let file = Container.shared.siriCatalogFile()
    db.startSiriCatalog(file)
    try await db.siriCatalogPublished()
    #expect(try await file.read().podcasts.isEmpty)
    let series = try await Container.shared.repo()
      .insertSeries(
        UnsavedPodcastSeries(
          unsavedPodcast: try Create.unsavedPodcast(title: "Show"),
          unsavedEpisodes: [try Create.unsavedEpisode(title: "Episode")]
        )
      )
    #expect(try await file.read().podcasts.flatMap(\.entries).map(\.title) == ["Show", "Episode"])
    try await db.writer.write { db in
      try Podcast.withID(series.podcast.id).updateAll(db, Podcast.Columns.title.set(to: "New show"))
    }
    #expect(
      try await file.read().podcasts.flatMap(\.entries).map(\.displayTitle) == [
        "New show", "Episode — New show",
      ]
    )
    do {
      try await db.writer.write { db in
        try Podcast.withID(series.podcast.id).deleteAll(db)
        throw URLError(.cancelled)
      }
    } catch {}
    #expect(try await file.read().podcasts.flatMap(\.entries).count == 2)
    try await Container.shared.repo().deletePodcast(series.podcast.id)
    #expect(try await file.read().podcasts.isEmpty)
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
    try await Container.shared.appDB().writer
      .write { db in
        let queries = ThreadSafe<[String]>([])
        db.trace { event in
          if case .statement(let statement) = event {
            queries { $0.append(statement.sql) }
          }
        }
        SiriCatalogPublisher(file: file).publish(db, trigger: .commit)
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
    let entries = try await file.read().podcasts.flatMap(\.entries)
    #expect(entries.count == 2)
    #expect(entries[0].identity.id == episode.podcast.id.rawValue)
    #expect(entries[0].title == episode.podcastTitle)
    #expect(entries[1].identity.id == episode.id.rawValue)
    #expect(entries[1].identity.feed == episode.feedURL.absoluteString)
    #expect(entries[1].identity.guid == episode.episode.guid.rawValue)
    #expect(entries[1].displayTitle == "Named episode — \(episode.podcastTitle)")
  }

  @Test("unavailable or invalidated catalog data never produces a handoff")
  func unavailableCatalog() async throws {
    let file = Container.shared.siriCatalogFile()
    let handler = SiriMediaIntentHandler(catalog: file.read, authorized: { true })
    let responses = ThreadSafe<[Int]>([])
    handler.handle(intent: SiriTestIntent.named("One")) { code in
      responses { $0.append(code.code.rawValue) }
    }
    try await Wait.until({ responses().count == 1 }, { "Missing unavailable callback" })
    try file.write(SiriCatalog(podcasts: [podcast(episodes: [(1, "One")])]))
    try file.invalidate()
    handler.handle(intent: SiriTestIntent.named("One")) { code in
      responses { $0.append(code.code.rawValue) }
    }
    try await Wait.until({ responses().count == 2 }, { "Missing invalidated callback" })
    #expect(
      responses() == Array(repeating: INPlayMediaIntentResponseCode.failure.rawValue, count: 2)
    )
  }

  @Test("extension confirms a unique request and hands audio to the app exactly once")
  func extensionHandoff() async throws {
    let show = podcast(episodes: [(1, "One")])
    let catalog = SiriCatalog(podcasts: [show])
    let handler = SiriMediaIntentHandler(catalog: { catalog }, authorized: { true })
    let responses = ThreadSafe<[Int]>([])
    handler.confirm(intent: SiriTestIntent.named("One")) { code in
      responses { $0.append(code.code.rawValue) }
    }
    try await Wait.until({ responses().count == 1 }, { "Missing confirmation callback" })
    handler.handle(intent: try SiriTestIntent.resolved(show.entry(for: show.episodes[0]))) { code in
      responses { $0.append(code.code.rawValue) }
    }
    try await Wait.until({ responses().count == 2 }, { "Missing handoff callback" })
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
    try await Wait.until({ responses().count == 3 }, { "Missing denied callback" })
    #expect(responses().last == INPlayMediaIntentResponseCode.failure.rawValue)
  }
}
