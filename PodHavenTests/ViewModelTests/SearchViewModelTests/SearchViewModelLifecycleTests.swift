// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Semaphore
import Testing

@testable import PodHaven

@Suite("of SearchViewModel lifecycle tests", .container)
@MainActor final class SearchViewModelLifecycleTests {
  @DynamicInjected(\.iTunesServiceSession) private var iTunesServiceSession
  @DynamicInjected(\.sleeper) private var sleeper

  private var session: FakeDataFetchable { iTunesServiceSession as! FakeDataFetchable }
  private var fakeSleeper: FakeSleeper { sleeper as! FakeSleeper }

  @Test("returning to Search keeps an in-flight typed search alive")
  func returningMidSearchKeepsInFlightSearchAlive() async throws {
    let topFeed = PreviewBundle.loadAsset(named: "top_feed", in: .iTunesResults)
    let topLookup = PreviewBundle.loadAsset(named: "top_lookup", in: .iTunesResults)
    let searchResults = PreviewBundle.loadAsset(named: "search_results", in: .iTunesResults)
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
        return (searchResults, URL.response(url))
      }
      return (url.dataRepresentation, URL.response(url))
    }

    let viewModel = SearchViewModel()
    viewModel.searchText = "growth"
    try await fakeSleeper.waitForSleepRequests(count: 1)
    await fakeSleeper.advanceTime(by: SearchViewModel.searchQueryDebounce)

    try await Wait.until(
      { @MainActor in viewModel.searchState == .loading },
      { @MainActor in
        "Expected search to enter .loading state, was \(viewModel.searchState)"
      }
    )

    // Leaving and returning to the tab must not cancel the in-flight search.
    viewModel.appear()
    #expect(
      viewModel.searchState == .loading,
      "Returning to Search cancelled the in-flight search"
    )

    // Releasing the hung response lets the original search finish in the
    // background and settle into its loaded results.
    searchHang.signal()

    try await Wait.until(
      { @MainActor in
        viewModel.searchState == .loaded && viewModel.searchResults.count == 2
      },
      { @MainActor in
        """
        Expected the in-flight search to finish in the background after returning.
        state: \(viewModel.searchState)
        results: \(viewModel.searchResults.count)
        """
      }
    )
  }

  @Test("returning to Search keeps an in-flight trending load alive")
  func returningMidTrendingKeepsInFlightLoadAlive() async throws {
    let topFeed = PreviewBundle.loadAsset(named: "top_feed", in: .iTunesResults)
    let topLookup = PreviewBundle.loadAsset(named: "top_lookup", in: .iTunesResults)
    let topHang = AsyncSemaphore(value: 0)

    await session.setDefaultHandler { url in
      if url.path.contains("/rss/toppodcasts") {
        try await topHang.waitUnlessCancelled()
        return (topFeed, URL.response(url))
      }
      if url.path.contains("/lookup") {
        return (topLookup, URL.response(url))
      }
      return (url.dataRepresentation, URL.response(url))
    }

    let viewModel = SearchViewModel()
    let fakeSession = session
    viewModel.appear()

    try await Wait.until(
      { @MainActor in
        viewModel.currentTrendingSection.state == .loading
      },
      { @MainActor in
        """
        Expected trending to enter .loading.
        state: \(viewModel.currentTrendingSection.state)
        """
      }
    )
    try await Wait.until(
      { await fakeSession.requests.contains { $0.path.contains("/rss/toppodcasts") } },
      {
        let requests = await fakeSession.requests
        return "Expected an in-flight top request; got \(requests)"
      }
    )

    // Returning to the tab must neither cancel nor restart the in-flight load.
    viewModel.appear()
    #expect(
      viewModel.currentTrendingSection.state == .loading,
      "Returning to Search disrupted the in-flight trending load"
    )

    // Releasing the hung response lets the original load finish in the
    // background rather than being cancelled and restarted.
    topHang.signal()

    try await Wait.until(
      { @MainActor in
        viewModel.currentTrendingSection.state == .loaded
          && viewModel.podcastList.allEntries.count == 3
      },
      { @MainActor in
        let requests = await fakeSession.requests
        return """
          Expected the in-flight trending load to finish in the background.
          state: \(viewModel.currentTrendingSection.state)
          entries: \(viewModel.podcastList.allEntries.count)
          requests: \(requests)
          """
      }
    )
  }

  @Test("returning to Search retries a trending section that failed its first load")
  func returningAfterTrendingErrorRetriesLoad() async throws {
    let topFeed = PreviewBundle.loadAsset(named: "top_feed", in: .iTunesResults)
    let topLookup = PreviewBundle.loadAsset(named: "top_lookup", in: .iTunesResults)
    // First top request fails (e.g. launched offline); every later one succeeds.
    let firstLoadShouldFail = ThreadSafe<Bool>(true)

    await session.setDefaultHandler { url in
      if url.path.contains("/rss/toppodcasts") {
        let shouldFail = firstLoadShouldFail { (flag: inout Bool) in
          let was = flag
          flag = false
          return was
        }
        if shouldFail { throw URLError(.notConnectedToInternet) }
        return (topFeed, URL.response(url))
      }
      if url.path.contains("/lookup") {
        return (topLookup, URL.response(url))
      }
      return (url.dataRepresentation, URL.response(url))
    }

    let viewModel = SearchViewModel()
    viewModel.appear()

    try await Wait.until(
      { @MainActor in
        if case .error = viewModel.currentTrendingSection.state { return true }
        return false
      },
      { @MainActor in
        "Expected the failed first load to land on .error; got \(viewModel.currentTrendingSection.state)"
      }
    )

    // Leaving and returning to the tab must retry the errored section rather
    // than leaving the user stuck on the error screen for the session.
    viewModel.appear()

    try await Wait.until(
      { @MainActor in
        viewModel.currentTrendingSection.state == .loaded
          && viewModel.podcastList.allEntries.count == 3
      },
      { @MainActor in
        """
        Expected returning to Search to retry the errored trending load.
        state: \(viewModel.currentTrendingSection.state)
        entries: \(viewModel.podcastList.allEntries.count)
        """
      }
    )
  }

  @Test("returning to Search retries a typed search that failed its first load")
  func returningAfterSearchErrorRetriesLoad() async throws {
    let topFeed = PreviewBundle.loadAsset(named: "top_feed", in: .iTunesResults)
    let topLookup = PreviewBundle.loadAsset(named: "top_lookup", in: .iTunesResults)
    let searchResults = PreviewBundle.loadAsset(named: "search_results", in: .iTunesResults)
    let firstSearchShouldFail = ThreadSafe<Bool>(true)

    await session.setDefaultHandler { url in
      if url.path.contains("/rss/toppodcasts") {
        return (topFeed, URL.response(url))
      }
      if url.path.contains("/lookup") {
        return (topLookup, URL.response(url))
      }
      if url.path.contains("/search") {
        let shouldFail = firstSearchShouldFail { (flag: inout Bool) in
          let was = flag
          flag = false
          return was
        }
        if shouldFail { throw URLError(.notConnectedToInternet) }
        return (searchResults, URL.response(url))
      }
      return (url.dataRepresentation, URL.response(url))
    }

    let viewModel = SearchViewModel()
    viewModel.searchText = "growth"
    try await fakeSleeper.waitForSleepRequests(count: 1)
    await fakeSleeper.advanceTime(by: SearchViewModel.searchQueryDebounce)

    try await Wait.until(
      { @MainActor in
        if case .error = viewModel.searchState { return true }
        return false
      },
      { @MainActor in
        "Expected the failed first search to land on .error; got \(viewModel.searchState)"
      }
    )

    viewModel.appear()

    try await Wait.until(
      { @MainActor in
        viewModel.searchState == .loaded
          && viewModel.isShowingSearchResults
          && viewModel.searchResults.count == 2
      },
      { @MainActor in
        """
        Expected returning to Search to retry the errored typed search.
        state: \(viewModel.searchState)
        searchedText: \(viewModel.searchedText)
        results: \(viewModel.searchResults.count)
        """
      }
    )
  }

  @Test("returning to Search does not retry an errored search after editing the query")
  func returningAfterSearchErrorWithEditedQueryDoesNotRetryStaleSearch() async throws {
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
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let term = components.queryItems?.first(where: { $0.name == "term" })?.value
        else {
          return (url.dataRepresentation, URL.response(url))
        }
        if term.contains("growth") { throw URLError(.notConnectedToInternet) }
        return (searchResults, URL.response(url))
      }
      return (url.dataRepresentation, URL.response(url))
    }

    func searchRequestCount(containing term: String) async -> Int {
      let requests = await session.requests
      return
        requests.filter { url in
          guard url.path.contains("/search"),
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let value = components.queryItems?.first(where: { $0.name == "term" })?.value
          else {
            return false
          }
          return value.contains(term)
        }
        .count
    }

    let viewModel = SearchViewModel()
    viewModel.searchText = "growth"
    try await fakeSleeper.waitForSleepRequests(count: 1)
    await fakeSleeper.advanceTime(by: SearchViewModel.searchQueryDebounce)

    try await Wait.until(
      { @MainActor in
        if case .error = viewModel.searchState { return true }
        return false
      },
      { @MainActor in
        "Expected the failed first search to land on .error; got \(viewModel.searchState)"
      }
    )
    let growthRequestsBeforeReturn = await searchRequestCount(containing: "growth")
    let pendingSleepsBeforeEdit = fakeSleeper.pendingCount()

    viewModel.searchText = "science"
    try await fakeSleeper.waitForSleepRequests(count: pendingSleepsBeforeEdit + 1)
    viewModel.appear()

    var stayedOnError = false
    if case .error = viewModel.searchState {
      stayedOnError = true
    }
    #expect(
      stayedOnError,
      "Returning with edited visible text must not retry the stale errored query"
    )
    #expect(await searchRequestCount(containing: "growth") == growthRequestsBeforeReturn)

    await fakeSleeper.advanceTime(by: SearchViewModel.searchQueryDebounce)

    try await Wait.until(
      { @MainActor in
        viewModel.searchState == .loaded
          && viewModel.isShowingSearchResults
          && viewModel.searchedText == "science"
          && viewModel.searchResults.count == 2
      },
      { @MainActor in
        """
        Expected the edited query to run after its debounce.
        state: \(viewModel.searchState)
        searchedText: \(viewModel.searchedText)
        results: \(viewModel.searchResults.count)
        """
      }
    )
    #expect(await searchRequestCount(containing: "growth") == growthRequestsBeforeReturn)
    #expect(await searchRequestCount(containing: "science") == 1)
  }

  // Leaving Search no longer tears anything down, so a pushed destination (e.g. a
  // discovery list backed by the still-alive collector) survives the round trip.
  @Test("returning to Search preserves a pushed discovery-list path")
  func returningToSearchPreservesPushedPath() async throws {
    await SearchViewModelTestHelpers.configureITunesResponses()

    let viewModel = SearchViewModel()
    let navigation = Container.shared.navigation()
    viewModel.appear()
    try await Wait.until(
      { @MainActor in viewModel.currentTrendingSection.state == .loaded },
      { @MainActor in "Expected trending to load before navigating" }
    )

    let source = SearchRecommendationCollector.Source.trending(.init(genreID: nil, title: "Top"))
    navigation.search.path = [
      Navigation.Destination.searchDiscovery(
        SearchDiscoveryListViewModel(collector: viewModel.recommendationCollector, source: source)
      )
    ]

    // Simulate leaving and returning to the tab.
    viewModel.appear()

    #expect(
      navigation.search.path.count == 1,
      "Expected returning to Search to preserve the pushed discovery list"
    )
  }

  @Test("a typed search survives leaving and returning to the Search tab")
  func typedSearchSurvivesTabSwitch() async throws {
    await SearchViewModelTestHelpers.configureITunesResponses()

    let viewModel = SearchViewModel()
    viewModel.appear()

    viewModel.searchText = "growth"
    try await fakeSleeper.waitForSleepRequests(count: 1)
    await fakeSleeper.advanceTime(by: SearchViewModel.searchQueryDebounce)

    try await Wait.until(
      { @MainActor in
        viewModel.searchState == .loaded
          && viewModel.isShowingSearchResults
          && viewModel.searchResults.count == 2
      },
      { @MainActor in "Expected the search to populate before leaving; got \(viewModel.searchState)"
      }
    )

    // Leaving the tab no longer tears down search state.
    #expect(viewModel.searchText == "growth", "Expected the typed query to survive leaving Search")
    #expect(viewModel.isShowingSearchResults, "Expected to stay in search mode after leaving")

    // Returning to the tab is a no-op; the results are still present.
    viewModel.appear()

    try await Wait.until(
      { @MainActor in
        viewModel.searchState == .loaded
          && viewModel.isShowingSearchResults
          && viewModel.searchResults.count == 2
      },
      { @MainActor in
        "Expected search results to be restored on return; got \(viewModel.searchState)"
      }
    )
  }

  @Test("a pending typed search survives leaving and returning to the Search tab")
  func pendingTypedSearchSurvivesTabSwitch() async throws {
    await SearchViewModelTestHelpers.configureITunesResponses()

    let viewModel = SearchViewModel()
    viewModel.appear()

    viewModel.searchText = "growth"
    try await fakeSleeper.waitForSleepRequests(count: 1)

    // Leaving the tab no longer cancels the pending debounced search.
    #expect(
      viewModel.searchText == "growth",
      "Expected the pending query to survive leaving Search"
    )

    // Returning is a no-op; the debounce fires on its own timer and the search
    // completes in the background.
    viewModel.appear()

    try await Wait.until(
      maxAttempts: 200,
      { @MainActor in
        await self.fakeSleeper.advanceTime(by: .milliseconds(100))
        return viewModel.searchState == .loaded
          && viewModel.isShowingSearchResults
          && viewModel.searchResults.count == 2
      },
      { @MainActor in
        """
        Expected the pending search to complete in the background after returning.
        state: \(viewModel.searchState)
        searchedText: \(viewModel.searchedText)
        searchText: \(viewModel.searchText)
        results: \(viewModel.searchResults.count)
        """
      }
    )
  }
}
