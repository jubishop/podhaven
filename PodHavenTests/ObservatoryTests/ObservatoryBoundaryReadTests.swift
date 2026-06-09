// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

// Direct boundary tests for Observatory observations that were previously
// exercised only transitively through view models / processors. Each test
// reads the observation's first emission via `.get()` and asserts on the
// returned value at the Observatory seam.
@Suite("of Observatory boundary read tests", .container)
actor ObservatoryBoundaryReadTests {
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.recommendationRepo) private var recommendationRepo

  // MARK: - Helpers

  @discardableResult
  private func createPodcastEpisode(rating: EpisodeRating? = nil) async throws -> PodcastEpisode {
    let podcastEpisodes = try await repo.upsertPodcastEpisodes([
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisode: try Create.unsavedEpisode(rating: rating)
      )
    ])
    return podcastEpisodes.first!
  }

  private func insertEmbedding(for episodeID: Episode.ID) async throws {
    try await recommendationRepo.upsertEmbeddings([
      UnsavedEpisodeEmbedding(
        episodeId: episodeID,
        vector: UnsavedEpisodeEmbedding.vectorData(from: [1.0, 0.0, 0.0]),
        sourceHash: "test-hash",
        embeddingRevision: 1,
        dimension: 3,
        verificationDate: Date()
      )
    ])
  }

  // MARK: - podcastCounts()

  @Test("podcastCounts() reports subscribed, unsubscribed, untagged, and per-tag counts")
  func testPodcastCounts() async throws {
    // A: subscribed + tagged. B: subscribed + untagged. C: unsubscribed + untagged.
    let a = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: try Create.unsavedPodcast(subscriptionDate: Date()))
    )
    _ = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: try Create.unsavedPodcast(subscriptionDate: Date()))
    )
    _ = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: try Create.unsavedPodcast(subscriptionDate: nil))
    )
    let tag = try await repo.insertTag(UnsavedTag(name: "news"))
    try await repo.addTag(tag.id, to: a.id)

    let counts = try await observatory.podcastCounts().get()
    #expect(counts.subscribed == 2)
    #expect(counts.unsubscribed == 1)
    #expect(counts.untagged == 2)
    #expect(counts.byTag[tag.id] == 1)
  }

  // MARK: - episodeIDs(filter:)

  @Test("episodeIDs(filter:) returns matching IDs and nothing for a non-matching filter")
  func testEpisodeIDs() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [try Create.unsavedEpisode(), try Create.unsavedEpisode()]
      )
    )
    let expected = Set(series.episodes.map(\.id))

    let matched =
      try await observatory.episodeIDs(
        filter: Episode.Columns.podcastId == series.podcast.id
      )
      .get()
    #expect(Set(matched) == expected)

    let none =
      try await observatory.episodeIDs(
        filter: Episode.Columns.podcastId == Podcast.ID(99999)
      )
      .get()
    #expect(none.isEmpty)
  }

  // MARK: - embeddedCandidateEpisodes(filter:)

  @Test("embeddedCandidateEpisodes(filter:) includes embedded candidates and omits unembedded ones")
  func testEmbeddedCandidateEpisodes() async throws {
    let embedded = try await createPodcastEpisode()
    let unembedded = try await createPodcastEpisode()
    try await insertEmbedding(for: embedded.episode.id)

    let result = try await observatory.embeddedCandidateEpisodes(filter: Episode.candidate).get()
    let ids = Set(result.map(\.id))
    #expect(ids.contains(embedded.episode.id))
    #expect(!ids.contains(unembedded.episode.id))
  }

  // MARK: - embeddingWorkSignal()

  @Test("embeddingWorkSignal() reflects whether any episode content exists")
  func testEmbeddingWorkSignal() async throws {
    let empty = try await observatory.embeddingWorkSignal().get()
    #expect(empty.latestEpisodeContentUpdate == nil)

    try await createPodcastEpisode()
    let populated = try await observatory.embeddingWorkSignal().get()
    #expect(populated.latestEpisodeContentUpdate != nil)
  }

  // MARK: - podcastSeriesDetail(_:)

  @Test(
    "podcastSeriesDetail(_:) observes the detail for an existing podcast and nil for a missing one"
  )
  func testPodcastSeriesDetail() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [try Create.unsavedEpisode()]
      )
    )

    let detail = try await observatory.podcastSeriesDetail(series.podcast.id).get()
    #expect(detail?.podcast.id == series.podcast.id)
    #expect(detail?.episodes.count == 1)

    let missing = try await observatory.podcastSeriesDetail(Podcast.ID(99999)).get()
    #expect(missing == nil)
  }
}
