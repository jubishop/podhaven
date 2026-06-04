// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of PodcastDetailViewModel row action tests", .container)
@MainActor final class RowActionTests {
  @DynamicInjected(\.repo) private var repo

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
}
