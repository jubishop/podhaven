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

  @Test("recommendationScore is hidden from the sort menu for unsaved podcasts")
  func recommendationScoreHiddenForUnsavedPodcasts() async throws {
    let unsavedSeries = UnsavedPodcastSeries(
      unsavedPodcast: try Create.unsavedPodcast(title: "Unsaved Preview"),
      unsavedEpisodes: [
        try Create.unsavedEpisode(guid: "a", title: "A"),
        try Create.unsavedEpisode(guid: "b", title: "B"),
      ]
    )
    let unsavedViewModel = PodcastDetailViewModel(unsavedPodcastSeries: unsavedSeries)
    #expect(!unsavedViewModel.allSortMethods.contains(.recommendationScore))

    let savedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(title: "Saved Detail"),
        unsavedEpisodes: [try Create.unsavedEpisode(guid: "x", title: "X")]
      )
    )
    let savedViewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(savedSeries.podcast))
    #expect(savedViewModel.allSortMethods.contains(.recommendationScore))
  }

  @Test("recommendationScore sort reorders episodes by score descending")
  func recommendationScoreSortReordersByScore() async throws {
    // Pin focused decone mode: exploratory strips three principal components
    // and on a fixture this small collapses score residuals to zero, which
    // would erase the ordering we're asserting.
    Container.shared.userSettings().$recommendationDeconeMode.new(.focused)

    // Engineered vectors give us a deterministic, monotonic similarity
    // gradient across candidates so the rec-score order is provably distinct
    // from newest-first. FakeEmbeddable derives vectors from String.hashValue,
    // which Swift re-seeds per process, so its candidate ordering was random
    // across CI runs and occasionally matched pubDate-descending.
    let embeddable = ScriptedEmbeddable { text in
      if text.contains("Filler") { return [0, 0, 1] }
      if text.contains("Signal") { return [1, 0, 0] }
      if text.contains("Target 0") { return [0.2, 0.98, 0] }
      if text.contains("Target 1") { return [0.4, 0.917, 0] }
      if text.contains("Target 2") { return [0.6, 0.8, 0] }
      if text.contains("Target 3") { return [0.8, 0.6, 0] }
      if text.contains("Target") { return [0, 1, 0] }
      return [0, 0, 1]
    }

    // Anchor the corpus mean off the signal/candidate cluster so mean-centering
    // preserves the engineered ordering. notInterested ratings keep these out
    // of both centroids and the candidate pool.
    let (_, fillers) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 10,
      podcastTitle: "Filler",
      podcastDescription: "Filler",
      episodeDescriptions: Array(repeating: "Filler", count: 10),
      ratings: Array(repeating: .notInterested, count: 10)
    )
    try await RecommendationHelpers.embedEpisodes(fillers, embeddable: embeddable)

    let (_, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      podcastDescription: "Signal",
      episodeDescriptions: ["Signal", "Signal", "Signal"],
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signals, embeddable: embeddable)

    // Descriptions carry the per-index discriminator the embeddable closure
    // matches on; titles share the constant "Target" branch so candidate
    // ordering comes entirely from descriptions.
    let (targetPodcast, candidateEpisodes) =
      try await RecommendationHelpers
      .createPodcastWithEpisodes(
        count: 4,
        podcastTitle: "Target",
        podcastDescription: "Target",
        episodeDescriptions: ["Target 0", "Target 1", "Target 2", "Target 3"]
      )
    try await RecommendationHelpers.embedEpisodes(candidateEpisodes, embeddable: embeddable)

    let scoreMap = try await RecommendationHelpers.startAndWaitForScores(
      for: candidateEpisodes
    )
    let expectedOrder =
      candidateEpisodes
      .sorted { lhs, rhs in
        let lhsScore = scoreMap[lhs.id]?.value ?? 0
        let rhsScore = scoreMap[rhs.id]?.value ?? 0
        if lhsScore != rhsScore { return lhsScore > rhsScore }
        if lhs.pubDate != rhs.pubDate { return lhs.pubDate > rhs.pubDate }
        if lhs.mediaGUID.guid != rhs.mediaGUID.guid {
          return lhs.mediaGUID.guid > rhs.mediaGUID.guid
        }
        return lhs.mediaGUID.mediaURL.rawValue.absoluteString
          > rhs.mediaGUID.mediaURL.rawValue.absoluteString
      }
      .map(\.id)
    // Engineered vectors make this guard hold by construction; keeping it
    // documents the contract and catches future fixture drift.
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

    // The recommendation observation work can inherit the poller's priority;
    // keep this above `.background` so CI load does not starve the sort update.
    try await Wait.until(
      priority: .userInitiated,
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
      priority: .userInitiated,
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
