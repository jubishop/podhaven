// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Semaphore
import Testing

@testable import PodHaven

@Suite("of SearchViewModel tests", .container)
@MainActor final class SearchViewModelTests {
  @DynamicInjected(\.iTunesServiceSession) private var iTunesServiceSession
  @DynamicInjected(\.podcastFeedSession) private var podcastFeedSession
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.sleeper) private var sleeper

  private var session: FakeDataFetchable { iTunesServiceSession as! FakeDataFetchable }
  private var feedSession: FakeDataFetchable { podcastFeedSession as! FakeDataFetchable }
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

  @Test("subscribing to a trending row removes its picks from the collector")
  func subscribingTrendingRowRemovesPicksFromCollector() async throws {
    let scripted = ScriptedEmbeddable { text in
      if text.contains("of Signal") {
        if text.contains("Episode 0") { return [1, 0, 0] }
        if text.contains("Episode 1") { return [0, 1, 0] }
        return [0, 0, 1]
      }
      return [1, 0, 0]
    }
    Container.shared.contextualEmbedding.reset()
      .register { ContextualEmbedding(embedding: scripted) }
      .scope(.cached)
    Container.shared.userSettings().$recommendationDeconeMode.new(.focused)
    let (_, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signals, embeddable: scripted)
    let engine = Container.shared.recommendationEngine()
    engine.start()
    try await RecommendationHelpers.untilAdvancing(
      { @Sendable in engine.hasScoringContext },
      { @Sendable in "Expected scoring context to land" }
    )

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

    await configureITunesResponses()
    await feedSession.respond(
      to: lennysFeed.rawValue,
      data: rssXML(
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
    let scripted = ScriptedEmbeddable { text in
      if text.contains("of Signal") {
        if text.contains("Episode 0") { return [1, 0, 0] }
        if text.contains("Episode 1") { return [0, 1, 0] }
        return [0, 0, 1]
      }
      return [1, 0, 0]
    }
    Container.shared.contextualEmbedding.reset()
      .register { ContextualEmbedding(embedding: scripted) }
      .scope(.cached)
    Container.shared.userSettings().$recommendationDeconeMode.new(.focused)
    let (_, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signals, embeddable: scripted)
    let engine = Container.shared.recommendationEngine()
    engine.start()
    try await RecommendationHelpers.untilAdvancing(
      { @Sendable in engine.hasScoringContext },
      { @Sendable in "Expected scoring context to land" }
    )

    let lennysFeed = FeedURL(URL(string: "https://api.substack.com/feed/podcast/10845.rss")!)
    await feedSession.respond(
      to: lennysFeed.rawValue,
      data: rssXML(
        title: "Lenny's",
        feedURL: lennysFeed,
        episodes: [
          ("lennys-pick", "Lenny Pick", Date(timeIntervalSince1970: 1_900_000_000))
        ]
      )
    )

    await configureITunesResponses(emptyForSearchTerm: "emptyterm")

    let viewModel = SearchViewModel()
    viewModel.appear()
    try await Wait.until(
      { @MainActor in viewModel.currentTrendingSection.state == .loaded },
      { @MainActor in "Expected trending to load before searching" }
    )

    viewModel.searchText = "growth"
    try await fakeSleeper.waitForSleepRequests(count: 1)
    await fakeSleeper.advanceTime(by: .milliseconds(400))

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
    await fakeSleeper.advanceTime(by: .milliseconds(400))

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
    let scripted = ScriptedEmbeddable { text in
      if text.contains("of Signal") {
        if text.contains("Episode 0") { return [1, 0, 0] }
        if text.contains("Episode 1") { return [0, 1, 0] }
        return [0, 0, 1]
      }
      return [1, 0, 0]
    }
    Container.shared.contextualEmbedding.reset()
      .register { ContextualEmbedding(embedding: scripted) }
      .scope(.cached)
    Container.shared.userSettings().$recommendationDeconeMode.new(.focused)
    let (_, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signals, embeddable: scripted)
    let engine = Container.shared.recommendationEngine()
    engine.start()
    try await RecommendationHelpers.untilAdvancing(
      { @Sendable in engine.hasScoringContext },
      { @Sendable in "Expected scoring context to land" }
    )

    let lennysFeed = FeedURL(URL(string: "https://api.substack.com/feed/podcast/10845.rss")!)
    await feedSession.respond(
      to: lennysFeed.rawValue,
      data: rssXML(
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
    await fakeSleeper.advanceTime(by: .milliseconds(400))

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
    await fakeSleeper.advanceTime(by: .milliseconds(400))

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

  private func rssXML(
    title: String,
    feedURL: FeedURL,
    episodes: [(guid: String, title: String, pubDate: Date)]
  ) -> Data {
    let pubDateFormatter = DateFormatter()
    pubDateFormatter.locale = Locale(identifier: "en_US_POSIX")
    pubDateFormatter.timeZone = TimeZone(identifier: "GMT")
    pubDateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"

    let items =
      episodes.map { entry -> String in
        """
        <item>
          <guid isPermaLink="false">\(entry.guid)</guid>
          <title>\(entry.title)</title>
          <pubDate>\(pubDateFormatter.string(from: entry.pubDate))</pubDate>
          <enclosure url="https://example.com/audio/\(entry.guid).mp3" type="audio/mpeg" length="0" />
          <description>\(entry.title) description</description>
        </item>
        """
      }
      .joined(separator: "\n")

    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
        <channel>
          <title>\(title)</title>
          <link>\(feedURL.absoluteString)</link>
          <description>\(title) description</description>
          <itunes:image href="https://example.com/image.png" />
          \(items)
        </channel>
      </rss>
      """
    return Data(xml.utf8)
  }

  private func configureITunesResponses(emptyForSearchTerm: String? = nil) async {
    let topFeed = PreviewBundle.loadAsset(named: "top_feed", in: .iTunesResults)
    let topLookup = PreviewBundle.loadAsset(named: "top_lookup", in: .iTunesResults)
    let searchResults = PreviewBundle.loadAsset(named: "search_results", in: .iTunesResults)
    let emptyResults = Data(#"{"resultCount":0,"results":[]}"#.utf8)

    await session.setDefaultHandler { url in
      if url.path.contains("/rss/toppodcasts") {
        return (topFeed, URL.response(url))
      }

      if url.path.contains("/lookup") {
        return (topLookup, URL.response(url))
      }

      if url.path.contains("/search") {
        if let emptyForSearchTerm,
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let term = components.queryItems?.first(where: { $0.name == "term" })?.value,
          term.contains(emptyForSearchTerm)
        {
          return (emptyResults, URL.response(url))
        }
        return (searchResults, URL.response(url))
      }

      return (url.dataRepresentation, URL.response(url))
    }
  }
}
