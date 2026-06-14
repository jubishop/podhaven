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

  @Test("podcastCounts() buckets all podcasts by freshness, queue, storage, and notify")
  func testPodcastCountsBySetting() async throws {
    // Mixed subscribed/unsubscribed; the buckets ignore subscription, like tags.
    _ = try await Create.podcast(
      subscriptionDate: Date(),
      queueAllEpisodes: .onTop,
      freshnessCadence: .daily
    )
    // Unsubscribed yet carries settings: still counted (no subscription filter).
    _ = try await Create.podcast(
      subscriptionDate: nil,
      queueAllEpisodes: .onTop,
      freshnessCadence: .daily
    )
    _ = try await Create.podcast(subscriptionDate: Date(), queueAllEpisodes: .onBottom)
    _ = try await Create.podcast(
      subscriptionDate: Date(),
      cacheAllEpisodes: .cache,
      freshnessCadence: .weekly
    )
    _ = try await Create.podcast(subscriptionDate: Date(), cacheAllEpisodes: .save)
    _ = try await Create.podcast(subscriptionDate: Date(), notifyNewEpisodes: true)
    // No settings, no episodes => indeterminate cadence, excluded from every bucket.
    _ = try await Create.podcast(subscriptionDate: Date())

    let counts = try await observatory.podcastCounts().get()
    #expect(counts.queueOnTop == 2)  // includes the unsubscribed show
    #expect(counts.queueOnBottom == 1)
    #expect(counts.autoCache == 1)
    #expect(counts.autoSave == 1)
    #expect(counts.notifyNewEpisodes == 1)

    #expect(counts.byFreshnessCadence[.daily] == 2)
    #expect(counts.byFreshnessCadence[.weekly] == 1)
    // Indeterminate shows contribute no cadence; empty cadences are omitted.
    #expect(counts.byFreshnessCadence[.hourly] == nil)
    #expect(counts.byFreshnessCadence.count == 2)
  }

  @Test("podcastCounts() resolves inferred cadence, and a manual cadence wins over it")
  func testPodcastCountsInferredFreshnessCadence() async throws {
    // Daily-spaced pubDates so inference resolves the show to .daily.
    func dailyEpisodes() throws -> [UnsavedEpisode] {
      let base = Date()
      return [
        try Create.unsavedEpisode(pubDate: base),
        try Create.unsavedEpisode(pubDate: base.addingTimeInterval(-86400)),
        try Create.unsavedEpisode(pubDate: base.addingTimeInterval(-172800)),
      ]
    }

    // No manual cadence: resolves only through the inferred fallback branch.
    _ = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(subscriptionDate: Date()),
        unsavedEpisodes: try dailyEpisodes()
      )
    )
    // Manual cadence set: wins over the conflicting inferred (.daily) cadence.
    _ = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(
          subscriptionDate: Date(),
          freshnessCadence: .weekly
        ),
        unsavedEpisodes: try dailyEpisodes()
      )
    )

    let counts = try await observatory.podcastCounts().get()
    #expect(counts.byFreshnessCadence[.daily] == 1)  // inferred-only show
    #expect(counts.byFreshnessCadence[.weekly] == 1)  // manual wins over inferred .daily
    #expect(counts.byFreshnessCadence.count == 2)
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
