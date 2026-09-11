// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("Silence cache content identity", .container)
struct SilenceCacheTests {
  @Test("replacing the same downloaded path gives it a new generation")
  func replacement() async throws {
    let episode = try await Create.podcastEpisode()
    let task = try await CacheHelpers.downloadToCache(episode.id)
    try await CacheHelpers.simulateBackgroundFinish(task, data: Data("first".utf8))
    let url = try await CacheHelpers.waitForCached(episode.id)
    let oldContent = try #require(
      try await Container.shared.silenceStore().content(for: url.lastPathComponent)
    )
    let db = Container.shared.appDB().unsafeTestDB
    let before = try await db.read { db in
      try String.fetchOne(
        db,
        sql: "SELECT generation FROM cachedAudioContent WHERE filename = ?",
        arguments: [url.lastPathComponent]
      )
    }
    #expect(before != nil)
    try await Container.shared.cacheFileStore()
      .discardInvalidFile(
        for: episode.id,
        cachedFilename: url.lastPathComponent
      )
    let nextTask = try await CacheHelpers.downloadToCache(episode.id)
    try await CacheHelpers.simulateBackgroundFinish(nextTask, data: Data("other".utf8))
    let replacement = try await CacheHelpers.waitForCached(episode.id)
    #expect(url == replacement)
    let after = try await db.read { db in
      try String.fetchOne(
        db,
        sql: "SELECT generation FROM cachedAudioContent WHERE filename = ?",
        arguments: [url.lastPathComponent]
      )
    }
    #expect(after != nil)
    #expect(before != after)
    #expect(
      try await !Container.shared.silenceStore()
        .publish(
          SilenceMap(duration: 30, intervals: [.init(start: 1, end: 2)]),
          for: oldContent
        )
    )
    _ = try await Container.shared.cacheManager().clearCache(for: episode.id)
    #expect(
      try await db.read { db in
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM cachedAudioContent")
      } == 0
    )
  }

  @Test("shared file references retain one map until the last reference is released")
  func sharedReferences() async throws {
    let mediaURL = MediaURL(try #require(URL(string: "https://example.com/silence-shared.mp3")))
    let (first, second) = try await Create.twoPodcastEpisodes(
      Create.unsavedEpisode(mediaURL: mediaURL),
      Create.unsavedEpisode(mediaURL: mediaURL)
    )
    let firstTask = try await CacheHelpers.downloadToCache(first.id)
    try await CacheHelpers.simulateBackgroundFinish(firstTask)
    let url = try await CacheHelpers.waitForCached(first.id)
    let store = Container.shared.silenceStore()
    let content = try #require(try await store.content(for: url.lastPathComponent))
    let map = SilenceMap(duration: 30, intervals: [.init(start: 1, end: 3)])
    try await store.publish(map, for: content)
    let secondTask = try await CacheHelpers.downloadToCache(second.id)
    try await CacheHelpers.simulateBackgroundFinish(secondTask)
    _ = try await CacheHelpers.waitForCached(second.id)
    _ = try await Container.shared.cacheManager().clearCache(for: first.id)
    #expect(try await store.content(for: url.lastPathComponent)?.generation == content.generation)
    #expect(try await store.content(for: url.lastPathComponent)?.map == map)
    _ = try await Container.shared.cacheManager().clearCache(for: second.id)
    #expect(try await store.content(for: url.lastPathComponent) == nil)
  }

  @Test("startup removes metadata whose media no longer exists")
  func orphanCleanup() async throws {
    try await Container.shared.appDB().unsafeTestDB
      .write { db in
        try db.execute(
          sql:
            "INSERT INTO cachedAudioContent (filename, generation) VALUES ('orphan.mp3', 'orphan')"
        )
      }
    try await Container.shared.silenceStore().pruneOrphans()
    #expect(
      try await Container.shared.appDB().reader
        .read { db in
          try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM cachedAudioContent")
        } == 0
    )
  }
}
