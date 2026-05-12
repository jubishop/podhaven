// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("of PodcastDetailViewModel sort and filter tests", .container)
@MainActor final class SortAndFilterTests {
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

    try await viewModel.performAppear()

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
      podcastSeries: savedSeries,
      podcast: nil,
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

    try await viewModel.performAppear()

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
      podcastSeries: savedSeries,
      podcast: nil,
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

  @Test("recommendationScore sort reorders episodes by score descending")
  func recommendationScoreSortReordersByScore() async throws {
    // Signal podcast supplies enough rated embeddings to lift the engine over
    // its minimum-data threshold; without this the cache stays cold and the
    // sort can't reorder.
    let (_, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signals)

    // Distinct titles → distinct FakeEmbeddable vectors → distinct similarity
    // scores against the signal centroid, so the rec-score order differs
    // from any natural property order.
    let (targetPodcast, candidateEpisodes) =
      try await RecommendationHelpers
      .createPodcastWithEpisodes(
        count: 4,
        podcastTitle: "Target"
      )
    try await RecommendationHelpers.embedEpisodes(candidateEpisodes)

    let scoreMap = try await RecommendationHelpers.startAndWaitForScores(
      for: candidateEpisodes
    )
    let expectedOrder =
      candidateEpisodes
      .sorted { lhs, rhs in
        let lhsValue = scoreMap[lhs.id]?.value ?? 0
        let rhsValue = scoreMap[rhs.id]?.value ?? 0
        return lhsValue > rhsValue
      }
      .map(\.id)
    // Guard against the case where the rec-score order happens to match
    // newest-first; a meaningful regression test must actually reorder.
    let newestFirstOrder =
      candidateEpisodes
      .sorted { $0.pubDate > $1.pubDate }
      .map(\.id)
    try #require(
      expectedOrder != newestFirstOrder,
      "Rec-score order matched newestFirst; the test wouldn't prove the sort applied."
    )

    let viewModel = PodcastDetailViewModel(
      podcast: DisplayedPodcast(targetPodcast)
    )
    try await viewModel.performAppear()

    try await Wait.until(
      { @MainActor in
        viewModel.saved
          && viewModel.episodeList.allEntries.count == candidateEpisodes.count
      },
      { @MainActor in
        """
        Expected target podcast to load all \(candidateEpisodes.count) episodes.
        saved: \(viewModel.saved)
        count: \(viewModel.episodeList.allEntries.count)
        """
      }
    )

    viewModel.currentSortMethod = .recommendationScore

    try await Wait.until(
      { @MainActor in
        viewModel.episodeList.filteredEntries.compactMap(\.episodeID) == expectedOrder
      },
      { @MainActor in
        """
        Expected episodes sorted by recommendation score descending.
        Expected: \(expectedOrder)
        Actual: \(viewModel.episodeList.filteredEntries.compactMap(\.episodeID))
        """
      }
    )
  }

  // Saved podcast detail intentionally filters by row title and parent podcast
  // title only. Episode.description stays outside the slim row so detail-list
  // hydration does not widen every saved detail read; adding description search
  // needs a deliberate alternate path rather than piggybacking on the row model.
  @Test(
    "saved podcast detail intentionally filters by episode and podcast title only"
  )
  func savedDetailFilterIsIntentionallyTitleOnly() async throws {
    let descriptionToken = "rutabaga-flagstone-3471"
    let titleToken = "tangerine-dropper"
    let podcastTitleToken = "kaleidoscope-cassette"
    let savedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(
          title: "Detail Search \(podcastTitleToken)",
          description: "Series-level blurb without any of the tokens"
        ),
        unsavedEpisodes: [
          try Create.unsavedEpisode(
            guid: "title-match",
            title: "Episode \(titleToken)",
            description: "intro with no special tokens"
          ),
          try Create.unsavedEpisode(
            guid: "description-only",
            title: "Episode With Plain Title",
            description: "intro that mentions \(descriptionToken)"
          ),
        ]
      )
    )
    let titleMatchID = savedSeries.episodes[0].id
    let descriptionOnlyID = savedSeries.episodes[1].id

    let viewModel = PodcastDetailViewModel(
      podcast: DisplayedPodcast(savedSeries.podcast)
    )
    try await viewModel.performAppear()

    try await Wait.until(
      { @MainActor in viewModel.episodeList.allEntries.count == 2 },
      { @MainActor in
        "Expected both saved episodes to load before filtering; got \(viewModel.episodeList.allEntries.count)"
      }
    )

    // Drop the debounce so each search term applies immediately.
    viewModel.episodeList.debounceDuration = .zero

    // Episode title token matches just the first row.
    viewModel.episodeList.entryFilter = titleToken
    try await Wait.until(
      { @MainActor in
        viewModel.episodeList.filteredEntries.map(\.episodeID) == [titleMatchID]
      },
      { @MainActor in
        """
        Expected episode-title token '\(titleToken)' to match the first row.
        filteredEntries: \(viewModel.episodeList.filteredEntries.map { ($0.title, $0.episodeID) })
        """
      }
    )

    // Podcast title token matches every row (both share the parent podcast).
    viewModel.episodeList.entryFilter = podcastTitleToken
    try await Wait.until(
      { @MainActor in
        viewModel.episodeList.filteredEntries.count == 2
      },
      { @MainActor in
        """
        Expected podcast-title token '\(podcastTitleToken)' to match both rows.
        filteredEntries: \(viewModel.episodeList.filteredEntries.map { ($0.title, $0.episodeID) })
        """
      }
    )

    // Description-only token must NOT match under this title-only contract.
    viewModel.episodeList.entryFilter = descriptionToken
    try await Wait.until(
      { @MainActor in viewModel.episodeList.filteredEntries.isEmpty },
      { @MainActor in
        """
        Expected description-only token '\(descriptionToken)' to filter to nothing on saved detail.
        If this test fails because filteredEntries now contains \(descriptionOnlyID), saved detail description search has been reintroduced. Make that product change explicit and keep it off the slim row model unless the query cost is acceptable.
        filteredEntries: \(viewModel.episodeList.filteredEntries.map { ($0.title, $0.episodeID) })
        """
      }
    )
  }
}
