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
    try await insertPodcast()

    let exportURL = TestFiles.uniqueURL().appendingPathExtension("sqlite")

    try appDB.exportSnapshot(to: exportURL)
    #expect(!FileManager.default.fileExists(atPath: exportURL.path + "-wal"))
    #expect(!FileManager.default.fileExists(atPath: exportURL.path + "-shm"))

    #expect(try await podcastCount(at: exportURL) == 1)
  }

  @Test("exportSnapshot(named:in:) keeps only the latest snapshot")
  func exportSnapshotInDirectoryKeepsLatest() async throws {
    let directory = TestFiles.uniqueURL()
    try await insertPodcast()
    let first = try appDB.exportSnapshot(named: "db.sqlite", in: directory)

    try await insertPodcast()
    let second = try appDB.exportSnapshot(named: "db.sqlite", in: directory)

    #expect(second == first)
    #expect(try FileManager.default.subpathsOfDirectory(atPath: directory.path) == ["db.sqlite"])
    #expect(try await podcastCount(at: second) == 2)
  }

  @Test("exportSnapshot(named:in:) leaves a reader its earlier snapshot")
  func exportSnapshotInDirectoryPreservesOpenReader() async throws {
    let directory = TestFiles.uniqueURL()
    try await insertPodcast()
    let first = try appDB.exportSnapshot(named: "db.sqlite", in: directory)
    let earlierData = try Data(contentsOf: first)
    let reader = try FileHandle(forReadingFrom: first)
    defer { try? reader.close() }

    try await insertPodcast()
    _ = try appDB.exportSnapshot(named: "db.sqlite", in: directory)

    #expect(try reader.readToEnd() == earlierData)
  }

  @Test("exportSnapshot(named:in:) removes leftovers of an interrupted export")
  func exportSnapshotInDirectoryRemovesLeftovers() async throws {
    let directory = TestFiles.uniqueURL()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("partial".utf8).write(to: directory.appendingPathComponent(UUID().uuidString))
    try await insertPodcast()

    let exportURL = try appDB.exportSnapshot(named: "db.sqlite", in: directory)

    #expect(try FileManager.default.subpathsOfDirectory(atPath: directory.path) == ["db.sqlite"])
    #expect(try await podcastCount(at: exportURL) == 1)
  }

  @Test("exportSnapshotData leaves no snapshot behind")
  func exportSnapshotDataRemovesDirectory() async throws {
    let directory = TestFiles.uniqueURL()
    try await insertPodcast()

    let data = try appDB.exportSnapshotData(in: directory)

    #expect(!FileManager.default.fileExists(atPath: directory.path))
    let copyURL = TestFiles.uniqueURL().appendingPathExtension("sqlite")
    try data.write(to: copyURL)
    #expect(try await podcastCount(at: copyURL) == 1)
  }

  // MARK: - Helpers

  private func insertPodcast() async throws {
    try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [try Create.unsavedEpisode()]
      )
    )
  }

  private func podcastCount(at url: URL) async throws -> Int {
    let exportDB = try DatabaseQueue(path: url.path)
    return try await exportDB.read { db in
      try Podcast.fetchCount(db)
    }
  }
}
