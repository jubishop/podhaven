// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("of PodcastDetailViewModel sort tests", .container)
@MainActor final class SortTests {
  @DynamicInjected(\.repo) private var repo

  @Test("recentlyQueued sort filters to previously queued episodes and orders newest first")
  func recentlyQueuedSortFiltersAndOrdersEpisodes() async throws {
    let olderQueueDate = Date(timeIntervalSince1970: 100)
    let newerQueueDate = Date(timeIntervalSince1970: 200)
    let unsavedSeries = UnsavedPodcastSeries(
      unsavedPodcast: try Create.unsavedPodcast(title: "Queue Sorting"),
      unsavedEpisodes: [
        try Create.unsavedEpisode(guid: "unqueued", title: "Not queued"),
        try Create.unsavedEpisode(
          guid: "older-queued",
          title: "Older queued",
          queueDate: olderQueueDate
        ),
        try Create.unsavedEpisode(
          guid: "newer-queued",
          title: "Newer queued",
          queueDate: newerQueueDate
        ),
      ]
    )
    let viewModel = PodcastDetailViewModel(unsavedPodcastSeries: unsavedSeries)
    try await PodcastDetailTestHelpers.appear(viewModel)

    viewModel.currentSortMethod = .recentlyQueued

    try await Wait.until(
      { @MainActor in
        viewModel.episodeList.filteredEntries.map(\.title) == ["Newer queued", "Older queued"]
      },
      { @MainActor in
        """
        Expected recentlyQueued sort to filter and order queued episodes.
        Actual titles: \(viewModel.episodeList.filteredEntries.map(\.title))
        """
      }
    )
  }

  @Test("refreshing a series under newestFirst places a new episode at the top, not the bottom")
  func refreshMergesNewEpisodeAtTopUnderNewestFirstSort() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/refresh-sort.rss")!)
    let olderPubDate = Date(timeIntervalSince1970: 100)
    let newerPubDate = Date(timeIntervalSince1970: 200)
    let newestPubDate = Date(timeIntervalSince1970: 300)
    let savedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(feedURL: feedURL, title: "Refresh Sort"),
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: "older", title: "Older", pubDate: olderPubDate),
          try Create.unsavedEpisode(guid: "newer", title: "Newer", pubDate: newerPubDate),
        ]
      )
    )
    let viewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(savedSeries.podcast))

    try await PodcastDetailTestHelpers.appear(viewModel)

    try await Wait.until(
      { @MainActor in
        viewModel.saved
          && viewModel.episodeList.allEntries.map(\.title) == ["Newer", "Older"]
      },
      { @MainActor in
        """
        Expected initial load to present episodes in newest-first order.
        saved: \(viewModel.saved)
        titles: \(viewModel.episodeList.allEntries.map(\.title))
        """
      }
    )

    try await repo.updateSeriesFromFeed(
      podcast: savedSeries.podcast,
      updatedPodcast: nil,
      unsavedEpisodes: [
        try Create.unsavedEpisode(guid: "newest", title: "Newest", pubDate: newestPubDate)
      ],
      existingEpisodes: []
    )

    try await Wait.until(
      { @MainActor in
        viewModel.episodeList.allEntries.map(\.title) == ["Newest", "Newer", "Older"]
      },
      { @MainActor in
        """
        Expected the refreshed new episode to land at the top under .newestFirst.
        titles: \(viewModel.episodeList.allEntries.map(\.title))
        """
      }
    )
  }

  @Test("switching sorts stays correct after a refresh merges a new episode")
  func switchingSortsStaysCorrectAfterRefreshMergesANewEpisode() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/sort-switch.rss")!)
    let olderPubDate = Date(timeIntervalSince1970: 100)
    let newerPubDate = Date(timeIntervalSince1970: 200)
    let newestPubDate = Date(timeIntervalSince1970: 300)
    let savedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(feedURL: feedURL, title: "Sort Switch"),
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: "older", title: "Older", pubDate: olderPubDate),
          try Create.unsavedEpisode(guid: "newer", title: "Newer", pubDate: newerPubDate),
        ]
      )
    )
    let viewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(savedSeries.podcast))

    try await PodcastDetailTestHelpers.appear(viewModel)

    try await Wait.until(
      { @MainActor in viewModel.saved && viewModel.episodeList.allEntries.count == 2 },
      { @MainActor in
        """
        Expected initial saved series to load with two episodes.
        saved: \(viewModel.saved)
        count: \(viewModel.episodeList.allEntries.count)
        """
      }
    )

    try await repo.updateSeriesFromFeed(
      podcast: savedSeries.podcast,
      updatedPodcast: nil,
      unsavedEpisodes: [
        try Create.unsavedEpisode(guid: "newest", title: "Newest", pubDate: newestPubDate)
      ],
      existingEpisodes: []
    )

    try await Wait.until(
      { @MainActor in viewModel.episodeList.allEntries.count == 3 },
      { @MainActor in
        "Expected the refreshed episode to be merged in (count == 3)."
      }
    )

    viewModel.currentSortMethod = .oldestFirst
    try await Wait.until(
      { @MainActor in
        viewModel.episodeList.filteredEntries.map(\.title) == ["Older", "Newer", "Newest"]
      },
      { @MainActor in
        """
        Expected oldestFirst to order by pubDate ascending.
        titles: \(viewModel.episodeList.filteredEntries.map(\.title))
        """
      }
    )

    viewModel.currentSortMethod = .newestFirst
    try await Wait.until(
      { @MainActor in
        viewModel.episodeList.filteredEntries.map(\.title) == ["Newest", "Newer", "Older"]
      },
      { @MainActor in
        """
        Expected newestFirst to re-sort by pubDate descending after the merge.
        titles: \(viewModel.episodeList.filteredEntries.map(\.title))
        """
      }
    )
  }
}
