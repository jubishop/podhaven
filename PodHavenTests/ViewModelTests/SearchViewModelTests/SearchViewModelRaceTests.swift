// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Semaphore
import Testing

@testable import PodHaven

@Suite("of SearchViewModel race tests", .container)
@MainActor final class SearchViewModelRaceTests {
  @DynamicInjected(\.iTunesServiceSession) private var iTunesServiceSession
  @DynamicInjected(\.sleeper) private var sleeper

  private var session: FakeDataFetchable { iTunesServiceSession as! FakeDataFetchable }
  private var fakeSleeper: FakeSleeper { sleeper as! FakeSleeper }

  // Regression: the failure path lacked the success path's check that its term
  // is still the searched text, so a search that failed after the query was
  // cleared still marked Search as failed.
  @Test("a search that fails after its query was cleared leaves Search alone")
  func staleSearchFailureIsIgnored() async throws {
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
        await searchHang.wait()
        throw URLError(.notConnectedToInternet)
      }
      return (url.dataRepresentation, URL.response(url))
    }

    try await LogCapture.withSink { sink in
      let viewModel = SearchViewModel()
      viewModel.searchText = "growth"
      try await fakeSleeper.waitForSleepRequests(count: 1)
      await fakeSleeper.advanceTime(by: SearchViewModel.searchQueryDebounce)
      let fakeSession = session
      try await Wait.until(
        { await fakeSession.requests.contains { $0.path.contains("/search") } },
        { "Expected the growth search to reach iTunes" }
      )

      viewModel.searchText = ""
      try await fakeSleeper.waitForSleepRequests(count: 1)
      await fakeSleeper.advanceTime(by: SearchViewModel.searchQueryDebounce)
      try await Wait.until(
        { @MainActor in
          !viewModel.isShowingSearchResults && viewModel.currentTrendingSection.state == .loaded
        },
        { @MainActor in
          "Expected clearing the query to show trending; got \(viewModel.currentTrendingSection.state)"
        }
      )
      let stateBeforeFailure = viewModel.searchState

      searchHang.signal()
      try await Wait.until(
        { sink.captured().contains { $0.message.contains("executeSearch: failed for term") } },
        { "Expected the cleared search to fail" }
      )

      #expect(viewModel.searchState == stateBeforeFailure)
    }
  }

  // Regression: a cancelled trending fetch cleared the section's task handle on
  // its way out, erasing the newer fetch's handle. A later refresh then couldn't
  // cancel that fetch, whose late failure overwrote the refreshed results.
  @Test("a trending fetch replaced by two quick refreshes can't overwrite the latest results")
  func supersededTrendingFetchCannotOverwriteLatest() async throws {
    let topFeed = PreviewBundle.loadAsset(named: "top_feed", in: .iTunesResults)
    let topLookup = PreviewBundle.loadAsset(named: "top_lookup", in: .iTunesResults)
    let initialHang = AsyncSemaphore(value: 0)
    let firstRefreshHang = AsyncSemaphore(value: 0)
    let topRequestCount = ThreadSafe(0)

    await session.setDefaultHandler { url in
      if url.path.contains("/rss/toppodcasts") {
        let request = topRequestCount { (count: inout Int) in
          count += 1
          return count
        }
        switch request {
        case 1:
          try await initialHang.waitUnlessCancelled()
        case 2:
          try await firstRefreshHang.waitUnlessCancelled()
          throw URLError(.notConnectedToInternet)
        default:
          break
        }
        return (topFeed, URL.response(url))
      }
      if url.path.contains("/lookup") {
        return (topLookup, URL.response(url))
      }
      return (url.dataRepresentation, URL.response(url))
    }

    try await LogCapture.withSink { sink in
      let viewModel = SearchViewModel()
      viewModel.appear()
      try await Wait.until(
        { topRequestCount() == 1 },
        { "Expected the initial trending fetch to start" }
      )

      let firstRefresh = Task { await viewModel.refreshCurrentTrendingSection() }
      try await Wait.until(
        {
          topRequestCount() == 2
            && sink.captured().contains {
              $0.message.contains("executeTrendingSectionFetch: failed")
            }
        },
        { "Expected the first refresh to start and the initial fetch to finish cancelled" }
      )

      await viewModel.refreshCurrentTrendingSection()
      #expect(viewModel.currentTrendingSection.state == .loaded)

      firstRefreshHang.signal()
      await firstRefresh.value

      try await Wait.until(
        { @MainActor in
          viewModel.currentTrendingSection.state == .loaded
            && viewModel.podcastList.allEntries.count == 3
        },
        { @MainActor in
          """
          Expected the superseded fetch to leave the refreshed results in place.
          state: \(viewModel.currentTrendingSection.state)
          entries: \(viewModel.podcastList.allEntries.count)
          """
        }
      )
    }
  }
}
