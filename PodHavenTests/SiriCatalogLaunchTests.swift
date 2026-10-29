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
    await #expect(throws: SiriMediaFailure.unavailable) {
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
}
