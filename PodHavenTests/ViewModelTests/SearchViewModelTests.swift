// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import IdentifiedCollections
import Semaphore
import Testing

@testable import PodHaven

@Suite("of SearchViewModel tests", .container)
@MainActor final class SearchViewModelTests {
  @DynamicInjected(\.iTunesServiceSession) private var iTunesServiceSession
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.sleeper) private var sleeper

  private var session: FakeDataFetchable { iTunesServiceSession as! FakeDataFetchable }
  private var fakeSleeper: FakeSleeper { sleeper as! FakeSleeper }

  @Test("appear loads the top trending podcasts")
  func appearLoadsTopTrendingPodcasts() async throws {
    await configureITunesResponses()

    let viewModel = SearchViewModel()
    viewModel.appear()

    try await Wait.until(
      { @MainActor in
        viewModel.currentTrendingSection.state == .loaded
          && viewModel.podcastList.allEntries.map(\.title)
            == [
              "Lenny's Podcast: Product | Growth | Career",
              "The Daily",
              "Science Friday",
            ]
      },
      { @MainActor in
        """
        Expected top trending podcasts to load in server order.
        state: \(viewModel.currentTrendingSection.state)
        titles: \(viewModel.podcastList.allEntries.map(\.title))
        """
      }
    )
  }

  @Test("debounced search shows search results and clearing restores trending results")
  func debouncedSearchShowsResultsAndClearingRestoresTrendingResults() async throws {
    await configureITunesResponses()

    let viewModel = SearchViewModel()
    viewModel.appear()

    try await Wait.until(
      { @MainActor in
        viewModel.currentTrendingSection.state == .loaded
          && !viewModel.podcastList.allEntries.isEmpty
      },
      { @MainActor in "Expected trending podcasts to load before searching" }
    )
    let trendingIDs = viewModel.podcastList.allEntries.ids.elements

    viewModel.searchText = " growth "
    try await fakeSleeper.waitForSleepRequests(count: 1)
    await fakeSleeper.advanceTime(by: .milliseconds(400))

    try await Wait.until(
      { @MainActor in
        viewModel.searchState == .loaded
          && viewModel.isShowingSearchResults
          && viewModel.searchResults.count == 2
          && viewModel.podcastList.allEntries.ids.elements == viewModel.searchResults.ids.elements
      },
      { @MainActor in
        """
        Expected debounced search to populate search results.
        state: \(viewModel.searchState)
        searchedText: \(viewModel.searchedText)
        result IDs: \(viewModel.searchResults.ids.elements)
        podcast list IDs: \(viewModel.podcastList.allEntries.ids.elements)
        """
      }
    )

    viewModel.searchText = "   "
    try await fakeSleeper.waitForSleepRequests(count: 1)
    await fakeSleeper.advanceTime(by: .milliseconds(400))

    try await Wait.until(
      { @MainActor in
        !viewModel.isShowingSearchResults
          && viewModel.searchResults.isEmpty
          && viewModel.podcastList.allEntries.ids.elements == trendingIDs
      },
      { @MainActor in
        """
        Expected clearing the search text to restore trending results.
        isShowingSearchResults: \(viewModel.isShowingSearchResults)
        searchResults: \(viewModel.searchResults.ids.elements)
        podcast list IDs: \(viewModel.podcastList.allEntries.ids.elements)
        trending IDs: \(trendingIDs)
        """
      }
    )
  }

  @Test("search results bridge saved podcasts by iTunes ID while preserving search identity")
  func searchResultsBridgeSavedPodcastsByITunesID() async throws {
    await configureITunesResponses()

    let iTunesID = ITunesPodcastID(1627920305)
    let canonicalFeedURL = FeedURL(URL(string: "https://example.com/lennys-canonical.rss")!)
    let searchFeedURL = FeedURL(URL(string: "https://api.substack.com/feed/podcast/10845.rss")!)
    let newestEpisodeDate = Date(timeIntervalSince1970: 321)

    try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(
          feedURL: canonicalFeedURL,
          iTunesID: iTunesID,
          title: "Canonical Lenny"
        ),
        unsavedEpisodes: [
          try Create.unsavedEpisode(
            guid: "canonical-lenny-1",
            title: "Canonical Episode",
            pubDate: newestEpisodeDate
          )
        ]
      )
    )

    let viewModel = SearchViewModel()
    viewModel.searchText = "growth"
    try await fakeSleeper.waitForSleepRequests(count: 1)
    await fakeSleeper.advanceTime(by: .milliseconds(400))

    try await Wait.until(
      { @MainActor in
        guard let bridged = viewModel.searchResults[id: searchFeedURL] else { return false }
        return bridged.podcast.id == canonicalFeedURL
          && bridged.podcast.slotID == searchFeedURL
          && bridged.podcast.feedURL == canonicalFeedURL
          && bridged.podcast.savedSearchResult != nil
          && bridged.podcast.podcastID != nil
          && bridged.episodeCount == 1
          && bridged.mostRecentEpisodeDate == newestEpisodeDate
      },
      { @MainActor in
        let bridged = viewModel.searchResults[id: searchFeedURL]
        return """
          Expected SearchViewModel to bridge a saved podcast onto the search result row.
          bridged exists: \(bridged != nil)
          canonical ID: \(String(describing: bridged?.podcast.id))
          slot ID: \(String(describing: bridged?.podcast.slotID))
          canonical feed: \(String(describing: bridged?.podcast.feedURL))
          saved search result: \(String(describing: bridged?.podcast.savedSearchResult))
          podcastID: \(String(describing: bridged?.podcast.podcastID))
          episodeCount: \(String(describing: bridged?.episodeCount))
          mostRecentEpisodeDate: \(String(describing: bridged?.mostRecentEpisodeDate))
          """
      }
    )

    let bridged = try #require(viewModel.searchResults[id: searchFeedURL])
    let resolved = try await bridged.podcast.getOrCreatePodcast()
    #expect(resolved.feedURL == canonicalFeedURL)
  }

  @Test("search results replace direct feedURL matches with the saved podcast")
  func searchResultsUpgradeDirectFeedURLMatches() async throws {
    await configureITunesResponses()

    let searchFeedURL = FeedURL(URL(string: "https://api.substack.com/feed/podcast/10845.rss")!)
    let newestEpisodeDate = Date(timeIntervalSince1970: 654)
    let subscriptionDate = Date(timeIntervalSince1970: 321)
    let savedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(
          feedURL: searchFeedURL,
          iTunesID: ITunesPodcastID(1627920305),
          title: "Saved Lenny",
          subscriptionDate: subscriptionDate
        ),
        unsavedEpisodes: [
          try Create.unsavedEpisode(
            guid: "saved-lenny-1",
            title: "Saved Episode",
            pubDate: newestEpisodeDate
          )
        ]
      )
    )

    let viewModel = SearchViewModel()
    viewModel.searchText = "growth"
    try await fakeSleeper.waitForSleepRequests(count: 1)
    await fakeSleeper.advanceTime(by: .milliseconds(400))

    try await Wait.until(
      { @MainActor in
        guard let bridged = viewModel.searchResults[id: searchFeedURL] else { return false }
        return bridged.podcast.id == searchFeedURL
          && bridged.podcast.podcastID == savedSeries.podcast.id
          && bridged.podcast.subscribed
          && bridged.podcast.savedSearchResult != nil
          && bridged.episodeCount == 1
          && bridged.mostRecentEpisodeDate == newestEpisodeDate
      },
      { @MainActor in
        let bridged = viewModel.searchResults[id: searchFeedURL]
        return """
          Expected SearchViewModel to replace a direct feedURL match with the saved podcast.
          bridged exists: \(bridged != nil)
          result ID: \(String(describing: bridged?.podcast.id))
          podcastID: \(String(describing: bridged?.podcast.podcastID))
          subscribed: \(String(describing: bridged?.podcast.subscribed))
          saved search result: \(String(describing: bridged?.podcast.savedSearchResult))
          episodeCount: \(String(describing: bridged?.episodeCount))
          mostRecentEpisodeDate: \(String(describing: bridged?.mostRecentEpisodeDate))
          """
      }
    )

    let bridged = try #require(viewModel.searchResults[id: searchFeedURL])
    let resolved = try await bridged.podcast.getOrCreatePodcast()
    #expect(resolved.id == savedSeries.podcast.id)
  }

  @Test("disappear clears stuck .loading state when a search is cancelled in flight")
  func disappearClearsStuckLoadingState() async throws {
    let topFeed = PreviewBundle.loadAsset(named: "top_feed", in: .iTunesResults)
    let topLookup = PreviewBundle.loadAsset(named: "top_lookup", in: .iTunesResults)
    let searchHang = AsyncSemaphore(value: 0)

    await session.setDefaultHandler { url in
      if url.path.contains("/rss/toppodcasts") {
        return (topFeed, URL.response(url))
      }
      if url.path.contains("/lookup") {
        return (topLookup, URL.response(url))
      }
      if url.path.contains("/search") {
        try await searchHang.waitUnlessCancelled()
        return (url.dataRepresentation, URL.response(url))
      }
      return (url.dataRepresentation, URL.response(url))
    }

    let viewModel = SearchViewModel()
    viewModel.searchText = "growth"
    try await fakeSleeper.waitForSleepRequests(count: 1)
    await fakeSleeper.advanceTime(by: .milliseconds(400))

    try await Wait.until(
      { @MainActor in viewModel.searchState == .loading },
      { @MainActor in
        "Expected search to enter .loading state, was \(viewModel.searchState)"
      }
    )

    viewModel.disappear()

    #expect(viewModel.searchState != .loading)
  }

  // MARK: - Sort modes keep nil-metadata podcasts visible

  @Test("byMostRecentEpisode keeps a result with no episode date visible, sorted last")
  func byMostRecentEpisodeKeepsNilEpisodeDateVisible() async throws {
    let withEpisodes = PodcastWithEpisodeMetadata(
      podcast: ListedPodcast(
        unsavedSearchResult: try Create.unsavedPodcast(
          feedURL: FeedURL(URL(string: "https://example.com/has-episodes.rss")!),
          title: "Has Episodes"
        )
      ),
      episodeCount: 3,
      mostRecentEpisodeDate: 5.minutesAgo
    )
    let noEpisodeDate = PodcastWithEpisodeMetadata(
      podcast: ListedPodcast(
        unsavedSearchResult: try Create.unsavedPodcast(
          feedURL: FeedURL(URL(string: "https://example.com/no-episode-date.rss")!),
          title: "No Episode Date"
        )
      ),
      episodeCount: 0,
      mostRecentEpisodeDate: nil
    )

    let viewModel = SearchViewModel()
    viewModel.currentSortMethod = .byMostRecentEpisode
    viewModel.podcastList.allEntries = IdentifiedArray(
      uniqueElements: [withEpisodes, noEpisodeDate]
    )
    try await Wait.until(
      { @MainActor in viewModel.podcastList.filteredEntryIDs.contains(withEpisodes.id) },
      { @MainActor in "list never settled; got \(viewModel.podcastList.filteredEntryIDs)" }
    )

    #expect(viewModel.podcastList.filteredEntryIDs == [withEpisodes.id, noEpisodeDate.id])
  }

  private func configureITunesResponses() async {
    let topFeed = PreviewBundle.loadAsset(named: "top_feed", in: .iTunesResults)
    let topLookup = PreviewBundle.loadAsset(named: "top_lookup", in: .iTunesResults)
    let searchResults = PreviewBundle.loadAsset(named: "search_results", in: .iTunesResults)

    await session.setDefaultHandler { url in
      if url.path.contains("/rss/toppodcasts") {
        return (topFeed, URL.response(url))
      }

      if url.path.contains("/lookup") {
        return (topLookup, URL.response(url))
      }

      if url.path.contains("/search") {
        return (searchResults, URL.response(url))
      }

      return (url.dataRepresentation, URL.response(url))
    }
  }
}
