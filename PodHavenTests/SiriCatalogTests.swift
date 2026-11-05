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

  @Test("background database commits publish inserts, renames, deletion, and rollback")
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
    try await db.siriCatalogPublished()
    #expect(try await file.read().podcasts.flatMap(\.entries).map(\.title) == ["Show", "Episode"])
    try await db.writer.write { db in
      try Podcast.withID(series.podcast.id).updateAll(db, Podcast.Columns.title.set(to: "New show"))
    }
    try await db.siriCatalogPublished()
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
    try await db.siriCatalogPublished()
    #expect(try await file.read().podcasts.isEmpty)
  }

  @Test("a commit publication keeps the app running in the background until it finishes")
  func backgroundPublication() async throws {
    let file = Container.shared.siriCatalogFile()
    let database = Container.shared.appDB().unsafeTestDB
    let publisher = SiriCatalogPublisher(file: file, reader: database)
    try await database.writeWithoutTransaction { publisher.observe($0) }
    // A synchronous write lets the publication task inherit the test's application.
    let insert: () throws -> Void = {
      try database.write { db in try Create.unsavedPodcast(title: "Show").insert(db) }
    }
    try insert()
    try await publisher.published()

    #expect(try await file.read().podcasts.map(\.title) == ["Show"])
    let application = try #require(await Container.shared.uiApplication() as? FakeApplication)
    let tasks = await application.taskIdentifiers(named: "siriCatalogPublication")
    #expect(tasks.count == 1)
    for task in tasks {
      #expect(await !application.hasActiveTask(identifier: task))
    }
  }

  @Test("the library revisions change exactly when a statement can change the catalog")
  func libraryRevision() async throws {
    let publisher = SiriCatalogPublisher(
      file: Container.shared.siriCatalogFile(),
      reader: Container.shared.appDB().unsafeTestDB
    )
    let series = try await Container.shared.repo()
      .insertSeries(
        UnsavedPodcastSeries(
          unsavedPodcast: try Create.unsavedPodcast(),
          unsavedEpisodes: [try Create.unsavedEpisode()]
        )
      )
    try await Container.shared.appDB().unsafeTestDB
      .write { db in
        func changes(
          _ revision: String = "revision",
          _ statement: () throws -> Void
        ) throws -> Bool {
          let query = "SELECT \(revision) FROM siriCatalogRevision"
          let before = try Int64.fetchOne(db, sql: query)
          try statement()
          return try Int64.fetchOne(db, sql: query) != before
        }
        for table in ["podcast", "episode"] {
          for column in try db.columns(in: table).map(\.name) {
            let update = "UPDATE \(table) SET \(column) = \(column)"
            #expect(
              try changes { try db.execute(sql: update) }
                == publisher.observes(
                  eventsOfKind: .update(tableName: table, columnNames: [column])
                ),
              "\(table).\(column)"
            )
            #expect(
              try changes("finishRevision") { try db.execute(sql: update) }
                == (table == "episode" && column == "finishDate"),
              "\(table).\(column) finish"
            )
          }
        }
        #expect(try changes { try Create.unsavedPodcast().insert(db) })
        #expect(
          try changes { try Create.unsavedEpisode(podcastId: series.podcast.id).insert(db) }
        )
        #expect(try changes { try Episode.withID(series.episodes[0].id).deleteAll(db) })
        #expect(try changes { try Podcast.withID(series.podcast.id).deleteAll(db) })
      }
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
    let database = Container.shared.appDB().unsafeTestDB
    let publisher = SiriCatalogPublisher(file: file, reader: database)
    let queries = ThreadSafe<[String]>([])
    try await database.writeWithoutTransaction { db in
      db.trace { event in
        if case .statement(let statement) = event {
          queries { $0.append(statement.sql) }
        }
      }
      publisher.observe(db)
      publisher.launch(db, openDuration: nil) {}
    }
    try await publisher.published()
    try await database.writeWithoutTransaction { db in
      db.trace(options: [])
      #expect(queries().contains { $0.contains("\"episode\"") })
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

  @Test(
    "a library past the read limit keeps its podcasts, unfinished, and newest finished episodes"
  )
  func boundedPublication() async throws {
    let file = Container.shared.siriCatalogFile()
    let database = Container.shared.appDB().unsafeTestDB
    let publisher = SiriCatalogPublisher(file: file, reader: database)
    try await database.writeWithoutTransaction { publisher.observe($0) }
    // About twice the limit; escaped quotes make encoded titles longer than their raw text.
    let podcastCount = 3
    let episodeCount = 16_800
    let unfinishedCount = 4_200
    let padding = "\"" + String(repeating: ".", count: 4_000) + "\""
    @Sendable func feed(_ podcast: Int) -> String { "https://private-sentinel.invalid/\(podcast)" }
    @Sendable func show(_ podcast: Int) -> String { "Private Sentinel Show \(podcast)" }
    @Sendable func guid(_ episode: Int) -> String { "private-sentinel-guid-\(episode)" }
    @Sendable func title(_ episode: Int) -> String {
      "Private Sentinel Episode \(episode) \(padding)"
    }
    // Synchronous writes let the publication task inherit the log sink.
    let seed: () throws -> Void = {
      try database.writeWithoutTransaction { db in
        try db.inTransaction {
          let podcastIDs = try (0..<podcastCount)
            .map { podcast in
              try Create.unsavedPodcast(
                feedURL: FeedURL(URL(string: feed(podcast))!),
                title: show(podcast)
              )
              .insertAndFetch(db, as: Podcast.self).id
            }
          // Newer episodes get lower IDs, so only publication dates order them.
          for episode in (0..<episodeCount).reversed() {
            try Create.unsavedEpisode(
              podcastId: podcastIDs[episode % podcastCount],
              guid: GUID(guid(episode)),
              title: title(episode),
              pubDate: Date(timeIntervalSince1970: TimeInterval(episode * 60)),
              finishDate: episode < unfinishedCount
                ? nil : Date(timeIntervalSince1970: TimeInterval(episode * 60 + 30))
            )
            .insert(db)
          }
          return .commit
        }
      }
    }
    let logs = try await LogCapture.withSink { sink in
      try seed()
      try await publisher.published()
      return sink.captured().filter { $0.message.hasPrefix("siriCatalogPublication ") }
    }

    let catalog = try await file.read()
    #expect(catalog.podcasts.map(\.title) == (0..<podcastCount).map(show))
    let published = Set(catalog.podcasts.flatMap(\.episodes).map(\.guid))
    let kept = (0..<episodeCount).filter { published.contains(guid($0)) }
    let keptFinished = kept.count - unfinishedCount
    #expect(published.count == kept.count)
    #expect(keptFinished > 0 && kept.count < episodeCount)
    #expect(
      kept == Array(0..<unfinishedCount) + Array((episodeCount - keptFinished)..<episodeCount)
    )
    for podcast in 0..<podcastCount {
      #expect(
        try catalog.matches(SiriTestIntent.named(show(podcast), type: .podcastShow))
          .map(\.identity.feed) == [feed(podcast)]
      )
    }
    func episodeIntent(_ episode: Int) -> INPlayMediaIntent {
      SiriTestIntent.named(
        title(episode),
        type: .podcastEpisode,
        album: show(episode % podcastCount)
      )
    }
    for episode in [0, episodeCount - 1] {
      #expect(try catalog.matches(episodeIntent(episode)).map(\.identity.guid) == [guid(episode)])
    }
    #expect(throws: SiriMediaFailure.noMatch) {
      try catalog.matches(episodeIntent(unfinishedCount))
    }

    #expect(logs.map(\.level) == [.warning])
    let message = try #require(logs.first?.message)
    #expect(
      message.contains(
        "podcasts=\(podcastCount) episodes=\(kept.count) omitted=\(episodeCount - kept.count) "
      )
    )
    #expect(message.contains("oversized=false"))
    for value in ["Private Sentinel", "private-sentinel"] {
      #expect(!message.contains(value), "Diagnostics must not include media metadata")
    }

    // Finishing the oldest unfinished episode makes it the first to omit.
    let finishOldest: () throws -> Void = {
      try database.writeWithoutTransaction { db in
        try db.inTransaction {
          try Episode.filter(Episode.Columns.guid == guid(0))
            .updateAll(db, Episode.Columns.finishDate.set(to: Date()))
          return .commit
        }
      }
    }
    let finishLogs = try await LogCapture.withSink { sink in
      try finishOldest()
      try await publisher.published()
      return sink.captured().filter { $0.message.hasPrefix("siriCatalogPublication ") }
    }
    let reprioritized = try await file.read()
    let republished = Set(reprioritized.podcasts.flatMap(\.episodes).map(\.guid))
    #expect(reprioritized.generation != catalog.generation)
    #expect(!republished.contains(guid(0)))
    #expect(republished.contains(guid(1)) && republished.contains(guid(episodeCount - 1)))
    #expect(finishLogs.count == 1)
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
