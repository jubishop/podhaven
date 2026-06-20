// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("of PodcastDetailViewModel freshness cadence tests", .container)
@MainActor final class PodcastDetailFreshnessCadenceTests {
  @DynamicInjected(\.repo) private var repo

  private func saveSeries(
    feedURL: String,
    dayOffsets: [Int]
  ) async throws -> PodcastSeries {
    try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(feedURL: FeedURL(URL(string: feedURL)!)),
        unsavedEpisodes: try dayOffsets.map { try Create.unsavedEpisode(pubDate: $0.daysAgo) }
      )
    )
  }

  private func appearedViewModel(
    for podcastID: Podcast.ID,
    expectedEpisodeCount: Int
  ) async throws -> PodcastDetailViewModel {
    let listablePodcast = try await PodcastDetailTestHelpers.fetchListablePodcast(podcastID)
    let viewModel = PodcastDetailViewModel(listedPodcast: ListedPodcast(saved: listablePodcast))
    viewModel.appear()
    try await Wait.until(
      { @MainActor in
        viewModel.saved && viewModel.episodeList.allEntries.count == expectedEpisodeCount
      },
      { @MainActor in
        """
        Expected appear to hydrate saved detail.
        expected entries: \(expectedEpisodeCount)
        actual entries: \(viewModel.episodeList.allEntries.count)
        podcast: \(viewModel.podcast.toString)
        """
      }
    )
    return viewModel
  }

  @Test("resolvedFreshnessCadence infers the cadence once enough episodes load")
  func infersCadenceFromEpisodes() async throws {
    let series = try await saveSeries(
      feedURL: "https://example.com/freshness-weekly.rss",
      dayOffsets: [0, 7, 14, 21, 28]
    )
    let viewModel = try await appearedViewModel(for: series.id, expectedEpisodeCount: 5)

    try await Wait.until(
      { @MainActor in viewModel.resolvedFreshnessCadence == .weekly },
      { @MainActor in
        "Expected weekly cadence, got \(String(describing: viewModel.resolvedFreshnessCadence))"
      }
    )
  }

  @Test("resolvedFreshnessCadence mirrors the PodcastsView bucket for sparse saved podcasts")
  func sparseSavedEpisodesUseBucketCadence() async throws {
    let series = try await saveSeries(
      feedURL: "https://example.com/freshness-sparse.rss",
      dayOffsets: [0, 7]
    )
    let viewModel = try await appearedViewModel(for: series.id, expectedEpisodeCount: 2)

    #expect(viewModel.episodeList.allEntries.count == 2)
    #expect(viewModel.resolvedFreshnessCadence == .weekly)
  }

  @Test("resolvedFreshnessCadence stays nil when a saved podcast has no freshness bucket")
  func nilWithoutFreshnessBucket() async throws {
    let series = try await saveSeries(
      feedURL: "https://example.com/freshness-empty.rss",
      dayOffsets: []
    )
    let viewModel = try await appearedViewModel(for: series.id, expectedEpisodeCount: 0)

    #expect(viewModel.episodeList.allEntries.isEmpty)
    #expect(viewModel.resolvedFreshnessCadence == nil)
  }

  @Test("resolvedFreshnessCadence prefers the manual override over inference")
  func prefersManualOverride() async throws {
    let series = try await saveSeries(
      feedURL: "https://example.com/freshness-override.rss",
      dayOffsets: [0, 7, 14, 21, 28]
    )
    var settings = PodcastSettings.defaults
    settings.freshnessCadence = .daily
    _ = try await repo.updatePodcastSettings(series.podcast.id, settings)
    let viewModel = try await appearedViewModel(for: series.id, expectedEpisodeCount: 5)

    try await Wait.until(
      { @MainActor in viewModel.resolvedFreshnessCadence == .daily },
      { @MainActor in
        "Expected daily override, got \(String(describing: viewModel.resolvedFreshnessCadence))"
      }
    )
  }
}
