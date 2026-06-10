// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("of SearchViewModel collector tests", .container)
@MainActor final class SearchViewModelCollectorTests {
  private typealias H = SearchRecommendationCollectorTestHelpers

  @DynamicInjected(\.iTunesServiceSession) private var iTunesServiceSession
  @DynamicInjected(\.podcastFeedSession) private var podcastFeedSession
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.sleeper) private var sleeper

  private var session: FakeDataFetchable { iTunesServiceSession as! FakeDataFetchable }
  private var feedSession: FakeDataFetchable { podcastFeedSession as! FakeDataFetchable }
  private var fakeSleeper: FakeSleeper { sleeper as! FakeSleeper }

  @Test("subscribing to a trending row removes its picks from the collector")
  func subscribingTrendingRowRemovesPicksFromCollector() async throws {
    try await H.primeEngine(embeddable: H.makeScriptedEmbeddable())

    // Lenny's is one of the rows in `top_lookup.json`; pre-insert as
    // unsubscribed-but-saved so the observation watches a real row.
    let lennysFeed = FeedURL(URL(string: "https://api.substack.com/feed/podcast/10845.rss")!)
    let lennysSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(
          feedURL: lennysFeed,
          iTunesID: ITunesPodcastID(1627920305),
          title: "Lenny's Stub",
          subscriptionDate: nil
        ),
        unsavedEpisodes: []
      )
    )

    await SearchViewModelTestHelpers.configureITunesResponses()
    await feedSession.respond(
      to: lennysFeed.rawValue,
      data: H.rssXML(
        title: "Lenny's",
        feedURL: lennysFeed,
        episodes: [
          ("lennys-pick", "Lenny Pick", Date(timeIntervalSince1970: 1_900_000_000))
        ]
      )
    )

    let viewModel = SearchViewModel()
    viewModel.appear()

    try await Wait.until(
      { @MainActor in viewModel.currentTrendingSection.state == .loaded },
      { @MainActor in "Expected trending to load" }
    )

    // Derive from `currentTrendingSection.title` so renames in
    // `AppIcon.trendingTop.text` don't silently make this assertion read
    // a never-populated source.
    let trendingSource = SearchRecommendationCollector.Source.trending(
      .init(
        genreID: viewModel.currentTrendingSection.genreID,
        title: viewModel.currentTrendingSection.title
      )
    )

    try await Wait.until(
      maxAttempts: 200,
      { @MainActor in
        await self.fakeSleeper.advanceTime(by: .milliseconds(100))
        return viewModel.recommendationCollector
          .picks(for: trendingSource)
          .contains { $0.episode.feedURL == lennysFeed }
      },
      { @MainActor in
        let pickURLs = viewModel.recommendationCollector
          .picks(for: trendingSource)
          .map(\.episode.feedURL.absoluteString)
        return "Expected lennys feedURL in picks before subscription; got \(pickURLs)"
      }
    )

    _ = try await repo.markSubscribed(lennysSeries.podcast.id)

    try await Wait.until(
      maxAttempts: 200,
      { @MainActor in
        await self.fakeSleeper.advanceTime(by: .milliseconds(100))
        return !viewModel.recommendationCollector
          .picks(for: trendingSource)
          .contains { $0.episode.feedURL == lennysFeed }
      },
      { @MainActor in
        let pickURLs = viewModel.recommendationCollector
          .picks(for: trendingSource)
          .map(\.episode.feedURL.absoluteString)
        return "Expected lennys pick to be removed after subscription; got \(pickURLs)"
      }
    )
  }

  @Test("typed-search overlay is dropped when the next query returns empty results")
  func emptyResultsNextQueryDropsPriorTypedSearchOverlay() async throws {
    try await H.primeEngine(embeddable: H.makeScriptedEmbeddable())

    let lennysFeed = FeedURL(URL(string: "https://api.substack.com/feed/podcast/10845.rss")!)
    await feedSession.respond(
      to: lennysFeed.rawValue,
      data: H.rssXML(
        title: "Lenny's",
        feedURL: lennysFeed,
        episodes: [
          ("lennys-pick", "Lenny Pick", Date(timeIntervalSince1970: 1_900_000_000))
        ]
      )
    )

    await SearchViewModelTestHelpers.configureITunesResponses(emptyForSearchTerm: "emptyterm")

    let viewModel = SearchViewModel()
    viewModel.appear()
    try await Wait.until(
      { @MainActor in viewModel.currentTrendingSection.state == .loaded },
      { @MainActor in "Expected trending to load before searching" }
    )

    viewModel.searchText = "growth"
    try await fakeSleeper.waitForSleepRequests(count: 1)
    await fakeSleeper.advanceTime(by: SearchViewModel.searchQueryDebounce)

    try await Wait.until(
      { @MainActor in viewModel.searchState == .loaded && !viewModel.searchResults.isEmpty },
      { @MainActor in "Expected 'growth' search results to land" }
    )

    let growthSource = SearchRecommendationCollector.Source.search(query: "growth")
    try await Wait.until(
      maxAttempts: 200,
      { @MainActor in
        await self.fakeSleeper.advanceTime(by: .milliseconds(100))
        return viewModel.recommendationCollector
          .picks(for: growthSource)
          .contains { $0.episode.feedURL == lennysFeed }
      },
      { @MainActor in
        let pickURLs = viewModel.recommendationCollector
          .picks(for: growthSource)
          .map(\.episode.feedURL.absoluteString)
        return "Expected lenny pick under 'growth' overlay; got \(pickURLs)"
      }
    )

    viewModel.searchText = "emptyterm"
    try await fakeSleeper.waitForSleepRequests(count: 1)
    await fakeSleeper.advanceTime(by: SearchViewModel.searchQueryDebounce)

    try await Wait.until(
      { @MainActor in
        viewModel.searchState == .loaded && viewModel.searchResults.isEmpty
      },
      { @MainActor in
        "Expected 'emptyterm' search to settle with empty results; state \(viewModel.searchState)"
      }
    )

    try await Wait.until(
      maxAttempts: 200,
      { @MainActor in
        await self.fakeSleeper.advanceTime(by: .milliseconds(100))
        return viewModel.recommendationCollector.picks(for: growthSource).isEmpty
      },
      { @MainActor in
        let pickURLs = viewModel.recommendationCollector
          .picks(for: growthSource)
          .map(\.episode.feedURL.absoluteString)
        return "Expected 'growth' overlay to be dropped after empty next query; got \(pickURLs)"
      }
    )
  }

  @Test("typed-search overlay is dropped when the next query errors")
  func erroringNextQueryDropsPriorTypedSearchOverlay() async throws {
    try await H.primeEngine(embeddable: H.makeScriptedEmbeddable())

    let lennysFeed = FeedURL(URL(string: "https://api.substack.com/feed/podcast/10845.rss")!)
    await feedSession.respond(
      to: lennysFeed.rawValue,
      data: H.rssXML(
        title: "Lenny's",
        feedURL: lennysFeed,
        episodes: [
          ("lennys-pick", "Lenny Pick", Date(timeIntervalSince1970: 1_900_000_000))
        ]
      )
    )

    let topFeed = PreviewBundle.loadAsset(named: "top_feed", in: .iTunesResults)
    let topLookup = PreviewBundle.loadAsset(named: "top_lookup", in: .iTunesResults)
    let searchResults = PreviewBundle.loadAsset(named: "search_results", in: .iTunesResults)
    await session.setDefaultHandler { url in
      if url.path.contains("/rss/toppodcasts") { return (topFeed, URL.response(url)) }
      if url.path.contains("/lookup") { return (topLookup, URL.response(url)) }
      if url.path.contains("/search") {
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let term = components.queryItems?.first(where: { $0.name == "term" })?.value,
          term.contains("errorterm")
        {
          throw URLError(.notConnectedToInternet)
        }
        return (searchResults, URL.response(url))
      }
      return (url.dataRepresentation, URL.response(url))
    }

    let viewModel = SearchViewModel()
    viewModel.appear()
    try await Wait.until(
      { @MainActor in viewModel.currentTrendingSection.state == .loaded },
      { @MainActor in "Expected trending to load" }
    )

    viewModel.searchText = "growth"
    try await fakeSleeper.waitForSleepRequests(count: 1)
    await fakeSleeper.advanceTime(by: SearchViewModel.searchQueryDebounce)

    try await Wait.until(
      { @MainActor in viewModel.searchState == .loaded && !viewModel.searchResults.isEmpty },
      { @MainActor in "Expected 'growth' search to land" }
    )

    let growthSource = SearchRecommendationCollector.Source.search(query: "growth")
    try await Wait.until(
      maxAttempts: 200,
      { @MainActor in
        await self.fakeSleeper.advanceTime(by: .milliseconds(100))
        return viewModel.recommendationCollector
          .picks(for: growthSource)
          .contains { $0.episode.feedURL == lennysFeed }
      },
      { @MainActor in
        let pickURLs = viewModel.recommendationCollector
          .picks(for: growthSource)
          .map(\.episode.feedURL.absoluteString)
        return "Expected lenny pick under 'growth' overlay; got \(pickURLs)"
      }
    )

    viewModel.searchText = "errorterm"
    try await fakeSleeper.waitForSleepRequests(count: 1)
    await fakeSleeper.advanceTime(by: SearchViewModel.searchQueryDebounce)

    try await Wait.until(
      { @MainActor in
        guard case .error = viewModel.searchState else { return false }
        return true
      },
      { @MainActor in
        "Expected 'errorterm' search to settle in .error state; state \(viewModel.searchState)"
      }
    )

    try await Wait.until(
      maxAttempts: 200,
      { @MainActor in
        await self.fakeSleeper.advanceTime(by: .milliseconds(100))
        return viewModel.recommendationCollector.picks(for: growthSource).isEmpty
      },
      { @MainActor in
        let pickURLs = viewModel.recommendationCollector
          .picks(for: growthSource)
          .map(\.episode.feedURL.absoluteString)
        return "Expected 'growth' overlay to be dropped after erroring next query; got \(pickURLs)"
      }
    )
  }
}
