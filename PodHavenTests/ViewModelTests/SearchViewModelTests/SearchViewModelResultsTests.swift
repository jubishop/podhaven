// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import IdentifiedCollections
import Testing

@testable import PodHaven

@Suite("of SearchViewModel results tests", .container)
@MainActor final class SearchViewModelResultsTests {
  @DynamicInjected(\.sleeper) private var sleeper

  private var fakeSleeper: FakeSleeper { sleeper as! FakeSleeper }

  @Test("appear loads the top trending podcasts")
  func appearLoadsTopTrendingPodcasts() async throws {
    await SearchViewModelTestHelpers.configureITunesResponses()

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
    await SearchViewModelTestHelpers.configureITunesResponses()

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
    await fakeSleeper.advanceTime(by: SearchViewModel.searchQueryDebounce)

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
    await fakeSleeper.advanceTime(by: SearchViewModel.searchQueryDebounce)

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
}
