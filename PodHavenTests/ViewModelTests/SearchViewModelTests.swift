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
    await fakeSleeper.advanceTime(by: SearchViewModel.searchQueryDebounce)

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
    await fakeSleeper.advanceTime(by: SearchViewModel.searchQueryDebounce)

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
    await fakeSleeper.advanceTime(by: SearchViewModel.searchQueryDebounce)

    try await Wait.until(
      { @MainActor in viewModel.searchState == .loading },
      { @MainActor in
        "Expected search to enter .loading state, was \(viewModel.searchState)"
      }
    )

    viewModel.disappear()

    #expect(viewModel.searchState != .loading)
  }

  @Test("disappear clears stuck .loading state when trending is cancelled in flight")
  func disappearClearsStuckTrendingLoadingState() async throws {
    let topFeed = PreviewBundle.loadAsset(named: "top_feed", in: .iTunesResults)
    let topLookup = PreviewBundle.loadAsset(named: "top_lookup", in: .iTunesResults)
    let searchResults = PreviewBundle.loadAsset(named: "search_results", in: .iTunesResults)
    let topHang = AsyncSemaphore(value: 0)

    await session.setDefaultHandler { url in
      if url.path.contains("/rss/toppodcasts") {
        try await topHang.waitUnlessCancelled()
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

    viewModel.disappear()
    await configureITunesResponses()
    viewModel.appear()

    try await Wait.until(
      { @MainActor in
        viewModel.currentTrendingSection.state == .loaded
          && viewModel.podcastList.allEntries.count == 3
      },
      { @MainActor in
        let requests = await fakeSession.requests
        return """
          Expected Search reappear to restart cancelled trending load.
          state: \(viewModel.currentTrendingSection.state)
          entries: \(viewModel.podcastList.allEntries.count)
          requests: \(requests)
          """
      }
    )
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
      data: SearchRecommendationCollectorTestHelpers.rssXML(
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
      data: SearchRecommendationCollectorTestHelpers.rssXML(
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
      data: SearchRecommendationCollectorTestHelpers.rssXML(
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

  // MARK: - Test: Disappear Resets Search Nav Stack To Root

  // Search always reopens at its top level, so leaving the tab clears any pushed
  // destinations (e.g. a discovery list that would otherwise be restored against
  // the just-reset collector cache).
  @Test("disappear resets the search navigation stack to its root")
  func disappearResetsSearchPathToRoot() throws {
    let viewModel = SearchViewModel()
    let navigation = Container.shared.navigation()
    let source = SearchRecommendationCollector.Source.trending(.init(genreID: nil, title: "Top"))
    navigation.search.path = [
      Navigation.Destination.searchDiscovery(source, viewModel.searchDiscoveryActionsViewModel)
    ]

    viewModel.disappear()

    #expect(
      navigation.search.path.isEmpty,
      "Expected leaving Search to reset the nav stack to its root"
    )
  }

  // MARK: - Test: Typed Search Survives A Tab Switch

  @Test("a typed search survives leaving and returning to the Search tab")
  func typedSearchSurvivesTabSwitch() async throws {
    await configureITunesResponses()

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

    // Leaving Search must preserve the typed query (it used to reset it).
    viewModel.disappear()
    #expect(viewModel.searchText == "growth", "Expected the typed query to survive leaving Search")
    #expect(viewModel.isShowingSearchResults, "Expected to stay in search mode after leaving")

    // Returning restores the search results rather than dropping to trending.
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
    await configureITunesResponses()

    let viewModel = SearchViewModel()
    viewModel.appear()

    viewModel.searchText = "growth"
    try await fakeSleeper.waitForSleepRequests(count: 1)

    viewModel.disappear()
    #expect(
      viewModel.searchText == "growth",
      "Expected the pending query to survive leaving Search"
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
        Expected pending search text to restore search results on return.
        state: \(viewModel.searchState)
        searchedText: \(viewModel.searchedText)
        searchText: \(viewModel.searchText)
        results: \(viewModel.searchResults.count)
        """
      }
    )
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
