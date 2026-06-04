// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

// Covers the repo write paths that maintain the cached `inferredFreshnessCadence`
// column (`insertSeries`, `updateSeriesFromFeed`, `upsertPodcastEpisodes`),
// observed through the resolved cadence map that recommendation scoring reads.
@Suite("of Repo freshness cadence tests", .container)
class RepoFreshnessCadenceTests {
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.recommendationRepo) private var recommendationRepo

  private let now = Date()

  private func unsavedEpisodes(atDayOffsets dayOffsets: [Double]) throws -> [UnsavedEpisode] {
    try dayOffsets.map { offset in
      try Create.unsavedEpisode(pubDate: now.addingTimeInterval(-offset * 86400))
    }
  }

  private func resolvedCadence(for podcastID: Podcast.ID) async throws -> FreshnessCadence? {
    try await recommendationRepo.allScoringContextInputs().freshnessCadences[podcastID]
  }

  @Test("insertSeries caches the inferred cadence from its episodes")
  func insertSeriesCachesCadence() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: try unsavedEpisodes(atDayOffsets: [0, 7, 14, 21, 28])
      )
    )
    #expect(try await resolvedCadence(for: series.podcast.id) == .weekly)
  }

  @Test("updateSeriesFromFeed recomputes the cached cadence when episodes arrive")
  func updateSeriesFromFeedRecomputes() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: try unsavedEpisodes(atDayOffsets: [100, 107, 114])
      )
    )
    #expect(try await resolvedCadence(for: series.podcast.id) == .weekly)

    _ = try await repo.updateSeriesFromFeed(
      podcastSeries: PodcastSeries(podcast: series.podcast),
      podcast: nil,
      unsavedEpisodes: try unsavedEpisodes(atDayOffsets: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]),
      existingEpisodes: []
    )
    #expect(try await resolvedCadence(for: series.podcast.id) == .daily)
  }

  @Test("upsertPodcastEpisodes caches each affected podcast independently in one batch")
  func upsertCachesPerPodcast() async throws {
    let dailyPodcast = try Create.unsavedPodcast()
    let weeklyPodcast = try Create.unsavedPodcast()
    let dailyEntries = try unsavedEpisodes(atDayOffsets: [0, 1, 2, 3, 4])
      .map {
        UnsavedPodcastEpisode(unsavedPodcast: dailyPodcast, unsavedEpisode: $0)
      }
    let weeklyEntries = try unsavedEpisodes(atDayOffsets: [0, 7, 14, 21, 28])
      .map {
        UnsavedPodcastEpisode(unsavedPodcast: weeklyPodcast, unsavedEpisode: $0)
      }

    let podcastEpisodes = try await repo.upsertPodcastEpisodes(dailyEntries + weeklyEntries)

    let dailyID = try #require(
      podcastEpisodes.first { $0.podcast.feedURL == dailyPodcast.feedURL }?.podcast.id
    )
    let weeklyID = try #require(
      podcastEpisodes.first { $0.podcast.feedURL == weeklyPodcast.feedURL }?.podcast.id
    )
    #expect(try await resolvedCadence(for: dailyID) == .daily)
    #expect(try await resolvedCadence(for: weeklyID) == .weekly)
  }
}
