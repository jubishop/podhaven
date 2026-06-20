// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import IdentifiedCollections
import Testing

@testable import PodHaven

@Suite("of SearchViewModel bridging tests", .container)
@MainActor final class SearchViewModelBridgingTests {
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.sleeper) private var sleeper

  private var fakeSleeper: FakeSleeper { sleeper as! FakeSleeper }

  @Test("search results bridge saved podcasts by iTunes ID while preserving search identity")
  func searchResultsBridgeSavedPodcastsByITunesID() async throws {
    await SearchViewModelTestHelpers.configureITunesResponses()

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
          && bridged.resolvedFreshnessCadence == .weekly
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
          resolvedFreshnessCadence: \(String(describing: bridged?.resolvedFreshnessCadence))
          """
      }
    )

    let bridged = try #require(viewModel.searchResults[id: searchFeedURL])
    let resolved = try await bridged.podcast.getOrCreatePodcast()
    #expect(resolved.feedURL == canonicalFeedURL)
  }

  @Test("search results replace direct feedURL matches with the saved podcast")
  func searchResultsUpgradeDirectFeedURLMatches() async throws {
    await SearchViewModelTestHelpers.configureITunesResponses()

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
          && bridged.resolvedFreshnessCadence == .weekly
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
          resolvedFreshnessCadence: \(String(describing: bridged?.resolvedFreshnessCadence))
          """
      }
    )

    let bridged = try #require(viewModel.searchResults[id: searchFeedURL])
    let resolved = try await bridged.podcast.getOrCreatePodcast()
    #expect(resolved.id == savedSeries.podcast.id)
  }
}
