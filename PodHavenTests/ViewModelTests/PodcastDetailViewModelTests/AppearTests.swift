// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("of PodcastDetailViewModel performAppear tests", .container)
@MainActor final class AppearTests {
  @DynamicInjected(\.podcastFeedSession) private var podcastFeedSession
  @DynamicInjected(\.repo) private var repo

  private var feedSession: FakeDataFetchable { podcastFeedSession as! FakeDataFetchable }

  @Test("performAppear loads a saved series and backfills its iTunes ID")
  func performAppearLoadsSavedSeriesAndBackfillsITunesID() async throws {
    let feedURL = FeedURL(URL(string: "https://feeds.simplecast.com/l2i9YnTd")!)
    let iTunesID = ITunesPodcastID(1528594034)
    let savedSeries = try await PodcastDetailTestHelpers.insertSeriesFromFeed(
      assetName: "hardfork_short",
      feedURL: feedURL
    )

    let viewModel = PodcastDetailViewModel(
      podcast: DisplayedPodcast(
        try Create.unsavedPodcast(
          feedURL: feedURL,
          iTunesID: iTunesID,
          title: "Hard Fork"
        )
      )
    )

    try await PodcastDetailTestHelpers.appear(viewModel)

    try await Wait.until(
      { @MainActor in
        let reloadedSeries = try await self.repo.podcastSeries(savedSeries.id)
        return viewModel.saved
          && viewModel.podcast.iTunesID == iTunesID
          && viewModel.episodeList.allEntries.count == savedSeries.episodes.count
          && reloadedSeries?.podcast.iTunesID == iTunesID
      },
      { @MainActor in
        let reloadedSeries = try await self.repo.podcastSeries(savedSeries.id)
        return """
          Expected PodcastDetailViewModel to load the saved series and backfill its iTunes ID.
          saved: \(viewModel.saved)
          podcast iTunesID: \(String(describing: viewModel.podcast.iTunesID))
          episode count: \(viewModel.episodeList.allEntries.count)
          reloaded iTunesID: \(String(describing: reloadedSeries?.podcast.iTunesID))
          """
      }
    )

    #expect(viewModel.podcast.title == savedSeries.podcast.title)
  }

  @Test("listed listable podcasts expose share URL and hydrate without parsing the feed")
  func listedListablePodcastsHydrateWithoutParsingFeed() async throws {
    let savedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(
          feedURL: FeedURL(URL(string: "https://example.com/listed-podcast.rss")!),
          title: "Listed Podcast",
          description: "Saved Description"
        ),
        unsavedEpisodes: [
          try Create.unsavedEpisode(title: "Episode 1"),
          try Create.unsavedEpisode(title: "Episode 2"),
        ]
      )
    )
    let listablePodcast = try await PodcastDetailTestHelpers.fetchListablePodcast(savedSeries.id)
    let viewModel = PodcastDetailViewModel(listedPodcast: ListedPodcast(saved: listablePodcast))

    #expect(viewModel.shareURL == ShareURL.podcast(feedURL: savedSeries.podcast.feedURL))

    try await PodcastDetailTestHelpers.appear(viewModel)

    try await Wait.until(
      { @MainActor in
        viewModel.saved
          && viewModel.podcast.title == savedSeries.podcast.title
          && viewModel.podcast.description == savedSeries.podcast.description
          && viewModel.episodeList.allEntries.count == savedSeries.episodes.count
      },
      { @MainActor in
        """
        Expected list-backed podcast detail to hydrate saved podcast data.
        saved: \(viewModel.saved)
        title: \(viewModel.podcast.title)
        description: \(viewModel.podcast.description)
        episode count: \(viewModel.episodeList.allEntries.count)
        """
      }
    )
  }

  @Test("listed search result podcasts preserve search metadata before hydrating saved detail")
  func listedSearchResultPodcastsPreserveInitialMetadata() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/search-target.rss")!)
    let iTunesID = ITunesPodcastID(777)
    let savedLink = try #require(URL(string: "https://example.com/saved"))
    let savedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(
          feedURL: feedURL,
          iTunesID: iTunesID,
          title: "Saved Podcast",
          description: "Saved Description",
          link: savedLink
        ),
        unsavedEpisodes: [try Create.unsavedEpisode(title: "Saved Episode")]
      )
    )
    let savedPodcast = try await PodcastDetailTestHelpers.fetchListablePodcast(savedSeries.id)
    let searchDescription = "Search Description"
    let searchLink = try #require(URL(string: "https://example.com/search"))
    let searchResult = SavedSearchResultPodcast(
      resultFeedURL: FeedURL(URL(string: "https://example.com/search-result.rss")!),
      originalPodcast: try Create.unsavedPodcast(
        feedURL: PodcastDetailTestHelpers.searchResultFeedURL(),
        iTunesID: iTunesID,
        title: "Search Title",
        description: searchDescription,
        link: searchLink
      ),
      originalEpisodeCount: 5,
      originalMostRecentEpisodeDate: Date(timeIntervalSince1970: 123),
      savedPodcast: savedPodcast
    )
    let viewModel = PodcastDetailViewModel(
      listedPodcast: ListedPodcast(savedSearchResult: searchResult)
    )

    #expect(viewModel.shareURL == ShareURL.podcast(feedURL: feedURL))
    #expect(viewModel.podcast.description == searchDescription)
    #expect(viewModel.podcast.link == searchLink)

    try await PodcastDetailTestHelpers.appear(viewModel)

    #expect(viewModel.saved)
    #expect(viewModel.podcast.description == savedSeries.podcast.description)
    #expect(viewModel.podcast.link == savedLink)
  }

  @Test("performAppear parses the feed when no saved series exists")
  func performAppearParsesFeedWhenUnsaved() async throws {
    let feedURL = FeedURL(URL(string: "https://feeds.simplecast.com/l2i9YnTd")!)
    let data = PreviewBundle.loadAsset(named: "hardfork_short", in: .FeedRSS)
    await feedSession.respond(to: feedURL.rawValue, data: data)
    let viewModel = PodcastDetailViewModel(
      podcast: DisplayedPodcast(
        try Create.unsavedPodcast(
          feedURL: feedURL,
          title: "Placeholder Title"
        )
      )
    )

    try await PodcastDetailTestHelpers.appear(viewModel)

    #expect(viewModel.saved == false)
    #expect(viewModel.podcast.loaded != nil)
    #expect(viewModel.episodeList.allEntries.isEmpty == false)
  }

  @Test("performAppear keeps preloaded unsaved series without reparsing the feed")
  func performAppearKeepsPreloadedUnsavedSeriesWithoutParsingFeed() async throws {
    let unsavedSeries = UnsavedPodcastSeries(
      unsavedPodcast: try Create.unsavedPodcast(
        feedURL: FeedURL(URL(string: "https://example.com/preloaded-series.rss")!),
        title: "Preloaded Series"
      ),
      unsavedEpisodes: [
        try Create.unsavedEpisode(
          guid: "preloaded-1",
          title: "Episode 1",
          pubDate: Date(timeIntervalSince1970: 200)
        ),
        try Create.unsavedEpisode(
          guid: "preloaded-2",
          title: "Episode 2",
          pubDate: Date(timeIntervalSince1970: 100)
        ),
      ]
    )
    let viewModel = PodcastDetailViewModel(unsavedPodcastSeries: unsavedSeries)

    try await PodcastDetailTestHelpers.appear(viewModel)

    #expect(viewModel.saved == false)
    #expect(viewModel.podcast.title == unsavedSeries.unsavedPodcast.title)
    #expect(viewModel.episodeList.allEntries.map(\.title) == ["Episode 1", "Episode 2"])
  }
}
