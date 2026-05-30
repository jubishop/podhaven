// Copyright Justin Bishop, 2025

import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of AppDB export", .container)
struct AppDBExportTests {
  @DynamicInjected(\.appDB) private var appDB
  @DynamicInjected(\.repo) private var repo

  @Test("exportSnapshot writes a standalone readable database")
  func exportSnapshotIsStandalone() async throws {
    try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [try Create.unsavedEpisode()]
      )
    )

    let exportURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("export-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: exportURL) }

    try appDB.exportSnapshot(to: exportURL)
    #expect(!FileManager.default.fileExists(atPath: exportURL.path + "-wal"))
    #expect(!FileManager.default.fileExists(atPath: exportURL.path + "-shm"))

    let exportDB = try DatabaseQueue(path: exportURL.path)
    let podcastCount = try await exportDB.read { db in
      try Podcast.fetchCount(db)
    }
    #expect(podcastCount == 1)
  }
}
