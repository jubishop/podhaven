// Copyright Justin Bishop, 2026

import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of Siri catalog launch publication", .container)
@MainActor struct SiriCatalogLaunchTests {
  private func committedLibrary(in directory: URL) throws -> String {
    let path = directory.appendingPathComponent("db.sqlite").path
    let queue = try DatabaseQueue(path: path)
    Schema.migrate(queue)
    try queue.write { db in
      let podcast = try Create.unsavedPodcast(title: "Committed show")
        .insertAndFetch(db, as: Podcast.self)
      _ = try Create.unsavedEpisode(podcastId: podcast.id, title: "Committed episode")
        .insertAndFetch(db, as: Episode.self)
    }
    try queue.close()
    return path
  }

  private func countedCatalog(in directory: URL) -> (SiriCatalogFile, ThreadSafe<Int>) {
    let writes = ThreadSafe(0)
    let file = SiriCatalogFile(
      url: directory.appendingPathComponent("siri-media.json"),
      replaceContents: { data, url in
        if !data.isEmpty { writes { $0 += 1 } }
        try data.write(to: url, options: .atomic)
      }
    )
    return (file, writes)
  }

  private func launchedGeneration(path: String, file: SiriCatalogFile) async throws -> UUID {
    let appDB = try AppDB.launch(path: path, siriCatalogFile: file)
    try await appDB.siriCatalogPublished()
    return try await file.read().generation
  }

  private func catalogFiles(in directory: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: directory.path)
      .filter { $0.hasPrefix("siri-media") }
  }

  @Test("launch initialization returns before publication and never exposes a stale catalog")
  func launchPublication() async throws {
    let directory = TestFiles.uniqueURL()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let path = try committedLibrary(in: directory)
    let url = directory.appendingPathComponent("siri-media.json")
    try SiriCatalogFile(url: url)
      .write(
        SiriCatalog(podcasts: [
          .init(id: 1, feed: "https://stale.test", title: "Stale show", episodes: [])
        ])
      )
    let storage = FakeSiriCatalogStorage()
    defer { storage.release() }

    let appDB = try AppDB.launch(
      path: path,
      siriCatalogFile: SiriCatalogFile(url: url, replaceContents: storage.replace)
    )

    #expect(storage.completedCatalogWrites() == 0, "Launch initialization waited for publication")
    try await Wait.until({ storage.catalogWriteHeld() }, { "Launch publication did not start" })
    await Task { @MainActor in MainActor.preconditionIsolated() }.value
    #expect(storage.completedCatalogWrites() == 0, "Main-actor work progresses during publication")
    await #expect(throws: (any Error).self) {
      try await SiriCatalogFile(url: url).read()
    }

    storage.release()
    try await appDB.siriCatalogPublished()
    #expect(
      try await SiriCatalogFile(url: url).read().podcasts.flatMap(\.entries).map(\.displayTitle)
        == [
          "Committed show", "Committed episode — Committed show",
        ]
    )
    #expect(storage.mainThreadCatalogWrites() == 0, "Publication must not write on the main thread")
  }

  @Test("a launch keeps a current catalog without republishing it")
  func currentCatalog() async throws {
    let directory = TestFiles.uniqueURL()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let path = try committedLibrary(in: directory)
    let (file, writes) = countedCatalog(in: directory)
    let published = try await launchedGeneration(path: path, file: file)

    let appDB = try AppDB.launch(path: path, siriCatalogFile: file)
    try await appDB.siriCatalogPublished()

    #expect(writes() == 1, "Launch republished a current catalog")
    #expect(try await file.read().generation == published)
    #expect(try catalogFiles(in: directory) == ["siri-media.json"])

    appDB.unsafeTestDB.add(transactionObserver: FailingCommit(), extent: .databaseLifetime)
    await #expect(throws: FailingCommit.Failure.self) {
      try await appDB.writer.write { db in
        try Podcast.all().updateAll(db, Podcast.Columns.title.set(to: "Failed show"))
      }
    }
    #expect(try await file.read().generation == published)

    try await appDB.writer.write { db in
      try Podcast.all().updateAll(db, Podcast.Columns.title.set(to: "Renamed show"))
    }
    let renamed = try await file.read()
    #expect(renamed.generation != published)
    #expect(renamed.podcasts.map(\.title) == ["Renamed show"])
    #expect(try await launchedGeneration(path: path, file: file) == renamed.generation)
  }

  enum Staleness: CaseIterable, Sendable {
    case relevantChange, crashBeforeRepublication, invalidFile, unstamped, schemaVersion, policy,
      migrations
  }

  @Test("a launch republishes a catalog it cannot verify as current", arguments: Staleness.allCases)
  func staleCatalog(_ staleness: Staleness) async throws {
    let directory = TestFiles.uniqueURL()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let path = try committedLibrary(in: directory)
    let (file, writes) = countedCatalog(in: directory)
    let published = try await launchedGeneration(path: path, file: file)
    var show = "Committed show"
    func edit(_ old: String, _ new: String) throws {
      let json = try String(contentsOf: file.url, encoding: .utf8)
      try #require(json.contains(old))
      try json.replacingOccurrences(of: old, with: new)
        .write(to: file.url, atomically: true, encoding: .utf8)
    }
    switch staleness {
    case .relevantChange, .crashBeforeRepublication:
      if staleness == .crashBeforeRepublication { try file.invalidate() }
      let queue = try DatabaseQueue(path: path)
      try await queue.write { db in try db.execute(sql: "UPDATE podcast SET title = 'Renamed show'")
      }
      try queue.close()
      show = "Renamed show"
    case .invalidFile:
      try file.invalidate()
    case .unstamped:
      try file.write(SiriCatalog(podcasts: try await file.read().podcasts))
    case .schemaVersion:
      let version = SiriCatalog.currentSchemaVersion
      try edit("\"schemaVersion\":\(version)", "\"schemaVersion\":\(version - 1)")
    case .policy:
      let policy = SiriCatalogPublisher.policyVersion
      try edit("\"policy\":\(policy)", "\"policy\":\(policy - 1)")
    case .migrations:
      let migrations = try #require(try await file.read().source?.migrations)
      try edit("\"migrations\":\(migrations)", "\"migrations\":\(migrations - 1)")
    }
    let writesBefore = writes()

    let appDB = try AppDB.launch(path: path, siriCatalogFile: file)
    try await appDB.siriCatalogPublished()

    let catalog = try await file.read()
    #expect(writes() == writesBefore + 1, "Launch kept a catalog it could not verify")
    #expect(catalog.generation != published)
    #expect(
      catalog.podcasts.flatMap(\.entries).map(\.displayTitle) == [
        show, "Committed episode — \(show)",
      ]
    )
    #expect(try catalogFiles(in: directory) == ["siri-media.json"])
  }
}

// Fails the first podcast commit after earlier observers prepared for it.
private final class FailingCommit: TransactionObserver, Sendable {
  struct Failure: Error {}
  private let changed = ThreadSafe(false)
  private let armed = ThreadSafe(true)

  func observes(eventsOfKind kind: DatabaseEventKind) -> Bool { kind.tableName == "podcast" }
  func databaseDidChange(with event: DatabaseEvent) { changed(true) }
  func databaseWillCommit() throws {
    guard changed(), armed() else { return }
    changed(false)
    armed(false)
    throw Failure()
  }
  func databaseDidCommit(_ db: Database) {}
  func databaseDidRollback(_ db: Database) { changed(false) }
}
