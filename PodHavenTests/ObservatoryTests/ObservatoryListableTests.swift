// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of Observatory listable tracked-region tests", .container)
actor ObservatoryListableTests {
  @DynamicInjected(\.appDB) private var appDB
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.repo) private var repo

  // MARK: - ListablePodcastEpisode

  @Test("ListablePodcastEpisode.request tracks only the columns it reads")
  func testListablePodcastEpisodeTrackedRegion() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [try Create.unsavedEpisode()]
      )
    )
    let episodeID = series.episodes[0].id
    let db = repo.db

    let region = try await db.read { db in
      try ListablePodcastEpisode.request(
        filter: Episode.Columns.id == episodeID
      )
      .databaseRegion(db)
    }

    // Episode columns ListablePodcastEpisode does NOT read must not trigger
    // (podcastId is tracked because GRDB needs it for the podcast JOIN)
    for column in ["description", "link"] {
      #expect(
        !region.isModified(
          byEventsOfKind: .update(tableName: "episode", columnNames: [column])
        ),
        "Region should not track episode column: \(column)"
      )
    }

    // Podcast columns ListablePodcastEpisode does NOT read must not trigger
    for column in [
      "description", "subscriptionDate", "lastUpdate", "notifyNewEpisodes",
      "queueAllEpisodes", "cacheAllEpisodes", "iTunesID", "link",
      "defaultPlaybackRate", "creationDate",
    ] {
      #expect(
        !region.isModified(
          byEventsOfKind: .update(tableName: "podcast", columnNames: [column])
        ),
        "Region should not track podcast column: \(column)"
      )
    }

    // Episode columns ListablePodcastEpisode DOES read must trigger
    for column in [
      "id", "guid", "mediaURL", "title", "pubDate", "duration",
      "image", "finishDate", "currentTime", "queueOrder", "saveInCache",
      "cachedFilename", "downloading", "podcastId", "creationDate",
      "queueDate",
    ] {
      #expect(
        region.isModified(
          byEventsOfKind: .update(tableName: "episode", columnNames: [column])
        ),
        "Region should track episode column: \(column)"
      )
    }

    // Podcast columns ListablePodcastEpisode DOES read must trigger
    // (id is tracked because GRDB needs it for the JOIN)
    for column in ["feedURL", "image", "title", "id"] {
      #expect(
        region.isModified(
          byEventsOfKind: .update(tableName: "podcast", columnNames: [column])
        ),
        "Region should track podcast column: \(column)"
      )
    }
  }

  @Test("recommendationHydrationEpisodes does not track playback progress columns")
  func recommendationHydrationEpisodeTrackedRegion() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [try Create.unsavedEpisode(currentTime: CMTime.seconds(42))]
      )
    )
    let episodeID = series.episodes[0].id
    let db = repo.db

    let rows =
      try await observatory.recommendationHydrationEpisodes(
        ids: [episodeID],
        limit: 10
      )
      .get()
    #expect(rows.first?.id == episodeID)
    #expect(rows.first?.currentTime == CMTime.seconds(42))

    let region = try await db.read { db in
      var region = DatabaseRegion()
      for trackedRegion in Observatory.recommendationHydrationTrackedRegions(ids: [episodeID]) {
        try region.formUnion(trackedRegion.databaseRegion(db))
      }
      return region
    }

    for column in ["currentTime", "maxPlaybackTime", "lastPlayedDate", "playbackCoverage"] {
      #expect(
        !region.isModified(
          byEventsOfKind: .update(tableName: "episode", columnNames: [column])
        ),
        "Region should not track playback column: \(column)"
      )
    }

    for column in ["title", "finishDate", "queueOrder", "cachedFilename"] {
      #expect(
        region.isModified(
          byEventsOfKind: .update(tableName: "episode", columnNames: [column])
        ),
        "Region should track display column: \(column)"
      )
    }
  }

  @Test("listable podcastEpisodes() does not trigger on description-only changes")
  func testListablePodcastEpisodeDescriptionDeduplication() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [try Create.unsavedEpisode()]
      )
    )
    let episodeID = series.episodes[0].id

    let updateCount = Counter()

    Task {
      let observation: AsyncValueObservation<[ListablePodcastEpisode]> =
        observatory.listablePodcastEpisodes(
          filter: Episode.Columns.id == episodeID
        )
      for try await _ in observation {
        await updateCount.increment()
      }
    }

    // Wait for initial emission
    try await updateCount.wait(for: 1)

    // Description changes should NOT cause new emissions
    try await appDB.db.write { db in
      try db.execute(
        sql: "UPDATE episode SET description = ? WHERE id = ?",
        arguments: ["Updated description", episodeID.rawValue]
      )
    }

    // Counter should still be at 1
    try await Wait.until(
      maxAttempts: 50,
      { await updateCount.maxValue == 1 },
      { "Expected maxValue to remain 1, got \(await updateCount.maxValue)" }
    )
  }

  @Test("listable podcastEpisodes() triggers on relevant column changes")
  func testListablePodcastEpisodeRelevantChanges() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [try Create.unsavedEpisode()]
      )
    )
    let episodeID = series.episodes[0].id

    let updateCount = Counter()

    Task {
      let observation: AsyncValueObservation<[ListablePodcastEpisode]> =
        observatory.listablePodcastEpisodes(
          filter: Episode.Columns.id == episodeID
        )
      for try await _ in observation {
        await updateCount.increment()
      }
    }

    // Wait for initial emission
    try await updateCount.wait(for: 1)

    // finishDate IS a tracked column
    _ = try await repo.markFinished(episodeID)
    try await updateCount.wait(for: 2)
  }

  // MARK: - ListablePodcast

  @Test(
    """
    PodcastWithEpisodeMetadata<ListablePodcast> tracks only the podcast columns \
    ListablePodcast reads
    """
  )
  func testListablePodcastTrackedRegion() async throws {
    try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [try Create.unsavedEpisode()]
      )
    )
    let db = repo.db

    let region = try await db.read { db in
      try PodcastWithEpisodeMetadata<ListablePodcast>
        .all()
        .databaseRegion(db)
    }

    // Podcast columns ListablePodcast does NOT read must not trigger
    for column in [
      "description", "link", "lastUpdate", "defaultPlaybackRate",
      "queueAllEpisodes", "cacheAllEpisodes", "notifyNewEpisodes",
    ] {
      #expect(
        !region.isModified(
          byEventsOfKind: .update(tableName: "podcast", columnNames: [column])
        ),
        "Region should not track podcast column: \(column)"
      )
    }

    // Podcast columns ListablePodcast DOES read must trigger
    for column in [
      "id", "creationDate", "feedURL", "iTunesID", "image", "title",
      "subscriptionDate",
    ] {
      #expect(
        region.isModified(
          byEventsOfKind: .update(tableName: "podcast", columnNames: [column])
        ),
        "Region should track podcast column: \(column)"
      )
    }
  }

  @Test("listable podcastsWithEpisodeMetadata() does not trigger on description-only changes")
  func testListablePodcastDescriptionDeduplication() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [try Create.unsavedEpisode()]
      )
    )

    let updateCount = Counter()

    Task {
      let observation: AsyncValueObservation<[PodcastWithEpisodeMetadata<ListablePodcast>]> =
        observatory.listablePodcastsWithEpisodeMetadata()
      for try await _ in observation {
        await updateCount.increment()
      }
    }

    // Wait for initial emission
    try await updateCount.wait(for: 1)

    // Description changes should NOT cause new emissions
    try await appDB.db.write { db in
      try db.execute(
        sql: "UPDATE podcast SET description = ? WHERE id = ?",
        arguments: ["Updated description", series.podcast.id.rawValue]
      )
    }

    // Counter should still be at 1
    try await Wait.until(
      maxAttempts: 50,
      { await updateCount.maxValue == 1 },
      { "Expected maxValue to remain 1, got \(await updateCount.maxValue)" }
    )
  }

  @Test("listable podcastsWithEpisodeMetadata() triggers on relevant column changes")
  func testListablePodcastRelevantChanges() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [try Create.unsavedEpisode()]
      )
    )

    let updateCount = Counter()

    Task {
      let observation: AsyncValueObservation<[PodcastWithEpisodeMetadata<ListablePodcast>]> =
        observatory.listablePodcastsWithEpisodeMetadata()
      for try await _ in observation {
        await updateCount.increment()
      }
    }

    // Wait for initial emission
    try await updateCount.wait(for: 1)

    // title IS a tracked column
    try await appDB.db.write { db in
      try db.execute(
        sql: "UPDATE podcast SET title = ? WHERE id = ?",
        arguments: ["New Title", series.podcast.id.rawValue]
      )
    }
    try await updateCount.wait(for: 2)
  }
}
