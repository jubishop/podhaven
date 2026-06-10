// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of CandidateEpisode tests", .container)
actor CandidateEpisodeTests {
  @DynamicInjected(\.appDB) private var appDB
  @DynamicInjected(\.recommendationRepo) private var recommendationRepo
  @DynamicInjected(\.repo) private var repo

  @Test("CandidateEpisode projection skips heavy Episode columns")
  func testCandidateEpisodeTrackedRegion() async throws {
    try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [try Create.unsavedEpisode()]
      )
    )
    let db = repo.db

    let region = try await db.read { db in
      try CandidateEpisode.filter(Episode.candidate).databaseRegion(db)
    }

    // Episode columns CandidateEpisode does NOT read must not be in the
    // projection's tracked region. The candidate filter touches
    // playbackStarted / finishDate / rating / queueOrder, so those are
    // tracked even though the projection skips them — keep them out of this
    // list. Per-tick playback columns (currentTime, maxPlaybackTime,
    // playbackCoverage, lastPlayedDate) must stay untracked so checkpoint
    // writes never wake candidate observations.
    for column in [
      "guid", "mediaURL", "title", "duration", "image", "link",
      "description", "creationDate", "queueDate", "saveInCache",
      "cachedFilename", "downloading", "ratingDate", "currentTime",
      "maxPlaybackTime", "playbackCoverage", "lastPlayedDate",
      "contentUpdatedAt",
    ] {
      #expect(
        !region.isModified(
          byEventsOfKind: .update(tableName: "episode", columnNames: [column])
        ),
        "Region should not track episode column: \(column)"
      )
    }

    // Projection columns must trigger.
    for column in ["id", "podcastId", "pubDate"] {
      #expect(
        region.isModified(
          byEventsOfKind: .update(tableName: "episode", columnNames: [column])
        ),
        "Region should track projection column: \(column)"
      )
    }

    // Filter columns must trigger so a candidate joining/leaving the pool
    // is detected (queueOrder/finishDate/rating/playbackStarted flips).
    for column in ["playbackStarted", "finishDate", "rating", "queueOrder"] {
      #expect(
        region.isModified(
          byEventsOfKind: .update(tableName: "episode", columnNames: [column])
        ),
        "Region should track candidate-filter column: \(column)"
      )
    }
  }

  @Test("allCandidateEpisodes returns the narrow projection for candidate rows")
  func testAllCandidateEpisodesReturnsCandidateEpisodes() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: "candidate", title: "Candidate"),
          try Create.unsavedEpisode(
            guid: "queued",
            title: "Queued",
            queueOrder: 0
          ),
          try Create.unsavedEpisode(
            guid: "rated",
            title: "Rated",
            rating: .liked,
            ratingDate: Date()
          ),
        ]
      )
    )
    let candidate = series.episodes[0]
    try await recommendationRepo.upsertEmbeddings(
      series.episodes.map {
        UnsavedEpisodeEmbedding(
          episodeId: $0.id,
          vector: UnsavedEpisodeEmbedding.vectorData(from: [1, 0, 0]),
          sourceHash: "test-hash",
          embeddingRevision: 1,
          dimension: 3,
          verificationDate: Date()
        )
      }
    )

    let candidates = try await recommendationRepo.allCandidateEpisodes()
    #expect(candidates.count == 1)
    let only = try #require(candidates.first)
    #expect(only.id == candidate.id)
    #expect(only.podcastID == series.podcast.id)
    #expect(only.pubDate == candidate.pubDate)
  }
}
