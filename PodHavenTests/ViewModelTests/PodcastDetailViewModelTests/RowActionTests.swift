// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of PodcastDetailViewModel row action tests", .container)
@MainActor final class RowActionTests {
  @DynamicInjected(\.repo) private var repo

  private var feedSession: FakeDataFetchable {
    Container.shared.podcastFeedSession() as! FakeDataFetchable
  }

  @Test("rating an episode on an unsaved podcast persists every episode, not just the rated one")
  func ratingUnsavedEpisodePersistsAllEpisodes() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/rate-unsaved.rss")!)
    let unsavedSeries = UnsavedPodcastSeries(
      unsavedPodcast: try Create.unsavedPodcast(feedURL: feedURL, title: "Rate Unsaved"),
      unsavedEpisodes: [
        try Create.unsavedEpisode(guid: "rate-1", title: "Episode 1"),
        try Create.unsavedEpisode(guid: "rate-2", title: "Episode 2"),
        try Create.unsavedEpisode(guid: "rate-3", title: "Episode 3"),
      ]
    )
    let viewModel = PodcastDetailViewModel(unsavedPodcastSeries: unsavedSeries)

    try await PodcastDetailTestHelpers.appear(viewModel)
    try await Wait.until(
      { @MainActor in viewModel.episodeList.allEntries.count == 3 },
      { @MainActor in
        "Expected the unsaved series to seed all episodes before rating; "
          + "entries=\(viewModel.episodeList.allEntries.count)"
      }
    )

    let target = try #require(
      viewModel.episodeList.allEntries.first { $0.title == "Episode 2" }
    )
    viewModel.rateEpisode(target, rating: .loved)

    // Rating persists the podcast, and observation then transitions to .saved.
    // Every episode must survive — the bug collapsed the list to the rated one.
    try await Wait.until(
      { @MainActor in viewModel.saved },
      { @MainActor in "Expected rating to persist the series; saved=\(viewModel.saved)" }
    )
    #expect(viewModel.episodeList.allEntries.count == 3)

    try await Wait.until(
      { @MainActor in
        guard let series = try await self.repo.podcastSeries(feedURL) else { return false }
        let rated = series.episodes.first { $0.title == "Episode 2" }
        return series.episodes.count == 3 && rated?.rating == .loved
      },
      { @MainActor in
        let series = try await self.repo.podcastSeries(feedURL)
        return """
          Expected the whole series persisted with the rating applied.
          repo episode count: \(series?.episodes.count ?? -1)
          rated episode rating: \
          \(String(describing: series?.episodes.first { $0.title == "Episode 2" }?.rating))
          """
      }
    )
  }

  @Test("saving an unsaved episode from a single-episode surface pulls the whole series")
  func savingUnsavedEpisodePullsWholeSeriesFromFeed() async throws {
    // Surfaces like Search-discovery / Episode-detail only hold one episode, so
    // persisting the whole series means pulling the feed. Drive the production
    // chokepoint directly with a stubbed multi-episode feed.
    let data = PreviewBundle.loadAsset(named: "hardfork_short", in: .FeedRSS)
    let parsed = try await PodcastFeed.parse(
      data,
      from: FeedURL(URL(string: "https://example.com/pull-series.rss")!)
    )
    let unsavedPodcast = try parsed.toUnsavedPodcast()
    let feedURL = unsavedPodcast.feedURL
    await feedSession.respond(to: feedURL.rawValue, data: data)

    let feedEpisodes = parsed.toUnsavedEpisodes()
    #expect(feedEpisodes.count > 1)
    let target = try #require(feedEpisodes.first)
    let actedOn = UnsavedPodcastEpisode(unsavedPodcast: unsavedPodcast, unsavedEpisode: target)

    let resolved = try await actedOn.getOrCreatePodcastEpisodeSavingSeries()
    #expect(resolved.mediaGUID == actedOn.mediaGUID)

    let series = try #require(try await repo.podcastSeries(feedURL))
    #expect(series.episodes.count == feedEpisodes.count)
  }

  @Test("saving an unsaved episode falls back to the lone episode when the feed pull fails")
  func savingUnsavedEpisodeFallsBackWhenFeedPullFails() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/offline-series.rss")!)
    await feedSession.respond(to: feedURL.rawValue, error: URLError(.notConnectedToInternet))

    let actedOn = UnsavedPodcastEpisode(
      unsavedPodcast: try Create.unsavedPodcast(feedURL: feedURL, title: "Offline Series"),
      unsavedEpisode: try Create.unsavedEpisode(guid: "offline-1", title: "Lone Episode")
    )

    let resolved = try await actedOn.getOrCreatePodcastEpisodeSavingSeries()
    #expect(resolved.mediaGUID == actedOn.mediaGUID)

    let series = try #require(try await repo.podcastSeries(feedURL))
    #expect(series.episodes.count == 1)
  }

  @Test("a bulk action on an unsaved selection persists the whole series, not just the selection")
  func bulkActionOnUnsavedSelectionPersistsWholeSeries() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/bulk-unsaved.rss")!)
    let unsavedSeries = UnsavedPodcastSeries(
      unsavedPodcast: try Create.unsavedPodcast(feedURL: feedURL, title: "Bulk Unsaved"),
      unsavedEpisodes: [
        try Create.unsavedEpisode(guid: "bulk-1", title: "Episode 1"),
        try Create.unsavedEpisode(guid: "bulk-2", title: "Episode 2"),
        try Create.unsavedEpisode(guid: "bulk-3", title: "Episode 3"),
      ]
    )
    let viewModel = PodcastDetailViewModel(unsavedPodcastSeries: unsavedSeries)

    try await PodcastDetailTestHelpers.appear(viewModel)
    try await Wait.until(
      { @MainActor in viewModel.episodeList.allEntries.count == 3 },
      { @MainActor in
        "Expected the unsaved series to seed all episodes before selecting; "
          + "entries=\(viewModel.episodeList.allEntries.count)"
      }
    )

    let target = try #require(viewModel.episodeList.allEntries.first { $0.title == "Episode 2" })
    viewModel.episodeList.isSelected[target.id] = true

    let podcastEpisodes = try await viewModel.selectedPodcastEpisodes
    #expect(podcastEpisodes.map(\.title) == ["Episode 2"])

    let series = try #require(try await repo.podcastSeries(feedURL))
    #expect(series.episodes.count == 3)
  }
}
