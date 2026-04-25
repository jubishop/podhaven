// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of ListedPodcast tests", .container)
class ListedPodcastTests {
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.repo) private var repo

  private func makeSearchResult(
    resultFeedURL: FeedURL,
    originalPodcast: UnsavedPodcast,
    savedPodcast: ListablePodcast,
    originalEpisodeCount: Int = 3,
    originalMostRecentEpisodeDate: Date? = Date(timeIntervalSince1970: 123)
  ) -> SavedSearchResultPodcast {
    SavedSearchResultPodcast(
      resultFeedURL: resultFeedURL,
      originalPodcast: originalPodcast,
      originalEpisodeCount: originalEpisodeCount,
      originalMostRecentEpisodeDate: originalMostRecentEpisodeDate,
      savedPodcast: savedPodcast
    )
  }

  private func fetchSavedPodcast(_ podcastID: Podcast.ID) async throws -> ListablePodcast {
    let results: [PodcastWithEpisodeMetadata<ListablePodcast>] =
      try await observatory.listablePodcastsWithEpisodeMetadata(
        { $0.filter(Podcast.Columns.id == podcastID) },
        limit: 1
      )
      .get()

    return try #require(results.first?.podcast)
  }

  // MARK: - ListedPodcast identity

  @Test("saved search result rows use result feed URL identity and canonical feed URL data")
  func testIdentitySeparation() async throws {
    let canonicalURL = FeedURL(URL(string: "https://example.com/canonical.rss")!)
    let searchURL = FeedURL(URL(string: "https://example.com/itunes.rss")!)
    let unsavedPodcast = try Create.unsavedPodcast(
      feedURL: canonicalURL,
      iTunesID: ITunesPodcastID(123),
      title: "Test Podcast"
    )
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: unsavedPodcast)
    )

    let listed = ListedPodcast(
      savedSearchResult: makeSearchResult(
        resultFeedURL: searchURL,
        originalPodcast: try Create.unsavedPodcast(
          feedURL: searchURL,
          iTunesID: ITunesPodcastID(123)
        ),
        savedPodcast: try await fetchSavedPodcast(series.podcast.id)
      )
    )

    #expect(listed.id == searchURL)
    #expect(listed.feedURL == canonicalURL)
    #expect(listed.id != listed.feedURL)
  }

  @Test("saved search result row identity equals canonical feed URL when URLs match")
  func testMatchingURLs() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/feed.rss")!)
    let unsavedPodcast = try Create.unsavedPodcast(feedURL: feedURL, title: "Same URL")
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: unsavedPodcast)
    )

    let listed = ListedPodcast(
      savedSearchResult: makeSearchResult(
        resultFeedURL: feedURL,
        originalPodcast: try Create.unsavedPodcast(feedURL: feedURL, title: "Same URL"),
        savedPodcast: try await fetchSavedPodcast(series.podcast.id)
      )
    )

    #expect(listed.id == listed.feedURL)
  }

  @Test("saved search result rows forward list fields from the saved podcast")
  func testFieldForwarding() async throws {
    let iTunesID = ITunesPodcastID(456)
    let unsavedPodcast = try Create.unsavedPodcast(
      iTunesID: iTunesID,
      title: "Forwarded Title",
      subscriptionDate: Date()
    )
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: unsavedPodcast)
    )
    let savedPodcast = try await fetchSavedPodcast(series.podcast.id)

    let listed = ListedPodcast(
      savedSearchResult: makeSearchResult(
        resultFeedURL: FeedURL(URL(string: "https://example.com/search.rss")!),
        originalPodcast: try Create.unsavedPodcast(
          feedURL: FeedURL(URL(string: "https://example.com/search.rss")!),
          iTunesID: iTunesID,
          title: "Original Search Title"
        ),
        savedPodcast: savedPodcast
      )
    )

    #expect(listed.title == "Forwarded Title")
    #expect(listed.iTunesID == iTunesID)
    #expect(listed.isSaved)
    #expect(listed.subscribed)
    #expect(listed.podcastID == series.podcast.id)
  }

  @Test("saved search result rows preserve original search metadata for reversion")
  func testOriginalSearchMetadata() async throws {
    let originalDate = Date(timeIntervalSince1970: 456)
    let originalPodcast = try Create.unsavedPodcast(
      feedURL: FeedURL(URL(string: "https://example.com/search.rss")!),
      title: "Original Search Title",
      description: "Original Search Description"
    )
    let savedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: try Create.unsavedPodcast(title: "Saved Podcast"))
    )
    let savedPodcast = try await fetchSavedPodcast(savedSeries.podcast.id)

    let listed = ListedPodcast(
      savedSearchResult: makeSearchResult(
        resultFeedURL: originalPodcast.feedURL,
        originalPodcast: originalPodcast,
        savedPodcast: savedPodcast,
        originalEpisodeCount: 7,
        originalMostRecentEpisodeDate: originalDate
      )
    )
    let metadata = try #require(
      listed.searchMetadata(episodeCount: 0, mostRecentEpisodeDate: nil)
    )

    #expect(metadata.podcast.title == "Original Search Title")
    #expect(metadata.episodeCount == 7)
    #expect(metadata.mostRecentEpisodeDate == originalDate)
  }

  // MARK: - Saved search result payload

  @Test("ListedPodcast.id returns resultFeedURL for saved search results")
  func testListedPodcastId() async throws {
    let canonicalURL = FeedURL(URL(string: "https://example.com/canonical.rss")!)
    let searchURL = FeedURL(URL(string: "https://example.com/search.rss")!)
    let unsavedPodcast = try Create.unsavedPodcast(feedURL: canonicalURL)
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: unsavedPodcast)
    )
    let savedPodcast = try await fetchSavedPodcast(series.podcast.id)

    let searchResult = makeSearchResult(
      resultFeedURL: searchURL,
      originalPodcast: try Create.unsavedPodcast(feedURL: searchURL),
      savedPodcast: savedPodcast
    )
    let listed = ListedPodcast(savedSearchResult: searchResult)

    #expect(listed.id == searchURL)
    #expect(listed.feedURL == canonicalURL)
  }

  @Test("ListedPodcast.getOrCreatePodcast() unwraps through saved search results")
  func testGetPodcastUnwrap() async throws {
    let unsavedPodcast = try Create.unsavedPodcast(title: "Unwrap Test")
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: unsavedPodcast)
    )
    let savedPodcast = try await fetchSavedPodcast(series.podcast.id)

    let searchResult = makeSearchResult(
      resultFeedURL: FeedURL(URL(string: "https://example.com/search.rss")!),
      originalPodcast: try Create.unsavedPodcast(
        feedURL: FeedURL(URL(string: "https://example.com/search.rss")!)
      ),
      savedPodcast: savedPodcast
    )
    let listed = ListedPodcast(savedSearchResult: searchResult)

    let unwrapped = try await listed.getOrCreatePodcast()
    #expect(unwrapped.id == series.podcast.id)
    #expect(unwrapped.feedURL == series.podcast.feedURL)
  }

  @Test("SavedSearchResultPodcast.getPodcast() unwraps through the saved podcast")
  func testSearchResultGetPodcast() async throws {
    let unsavedPodcast = try Create.unsavedPodcast(title: "Search Helper")
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: unsavedPodcast)
    )
    let savedPodcast = try await fetchSavedPodcast(series.podcast.id)

    let searchResult = makeSearchResult(
      resultFeedURL: FeedURL(URL(string: "https://example.com/search-helper.rss")!),
      originalPodcast: try Create.unsavedPodcast(
        feedURL: FeedURL(URL(string: "https://example.com/search-helper.rss")!)
      ),
      savedPodcast: savedPodcast
    )

    let resolved = try await searchResult.getPodcast()
    #expect(resolved.id == series.podcast.id)
    #expect(resolved.feedURL == series.podcast.feedURL)
  }

  @Test("ListedPodcast.getOrCreatePodcast() returns the real Podcast")
  func testGetOrCreatePodcast() async throws {
    let canonicalURL = FeedURL(URL(string: "https://example.com/canonical.rss")!)
    let unsavedPodcast = try Create.unsavedPodcast(
      feedURL: canonicalURL,
      title: "Real Podcast"
    )
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: unsavedPodcast)
    )
    let savedPodcast = try await fetchSavedPodcast(series.podcast.id)

    let searchResult = makeSearchResult(
      resultFeedURL: FeedURL(URL(string: "https://example.com/search.rss")!),
      originalPodcast: try Create.unsavedPodcast(
        feedURL: FeedURL(URL(string: "https://example.com/search.rss")!)
      ),
      savedPodcast: savedPodcast
    )
    let listed = ListedPodcast(savedSearchResult: searchResult)

    let resolved = try await listed.getOrCreatePodcast()
    #expect(resolved.id == series.podcast.id)
    #expect(resolved.feedURL == canonicalURL)
  }

  @Test("ListablePodcast.getPodcast() returns the real Podcast")
  func testListablePodcastGetPodcast() async throws {
    let unsavedPodcast = try Create.unsavedPodcast(title: "Listable Helper")
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: unsavedPodcast)
    )
    let savedPodcast = try await fetchSavedPodcast(series.podcast.id)

    let resolved = try await savedPodcast.getPodcast()
    #expect(resolved.id == series.podcast.id)
    #expect(resolved.feedURL == series.podcast.feedURL)
  }

  @Test("ListedPodcast exposes original search metadata for saved search results")
  func testOriginalSearchMetadataForSavedSearchResult() async throws {
    let canonicalURL = FeedURL(URL(string: "https://example.com/canonical.rss")!)
    let unsavedPodcast = try Create.unsavedPodcast(
      feedURL: canonicalURL,
      subscriptionDate: Date()
    )
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: unsavedPodcast)
    )
    let savedPodcast = try await fetchSavedPodcast(series.podcast.id)
    let originalSearchPodcast = try Create.unsavedPodcast(
      feedURL: FeedURL(URL(string: "https://example.com/search.rss")!),
      title: "Search Title"
    )

    let searchResult = makeSearchResult(
      resultFeedURL: originalSearchPodcast.feedURL,
      originalPodcast: originalSearchPodcast,
      savedPodcast: savedPodcast
    )
    let listed = ListedPodcast(savedSearchResult: searchResult)

    let metadata = try #require(
      listed.searchMetadata(episodeCount: 0, mostRecentEpisodeDate: nil)
    )
    let original = try metadata.podcast.toOriginalUnsavedPodcast()
    #expect(original.feedURL == originalSearchPodcast.feedURL)
    #expect(original.subscriptionDate == nil)
  }

  // MARK: - iTunesID bridge scenario (exercises the same guarantees as buildUpdatedResult)

  @Test("saved search result in ListedPodcast preserves all search/trending invariants")
  func testBridgedSearchResultInvariants() async throws {
    let canonicalURL = FeedURL(URL(string: "https://example.com/canonical.rss")!)
    let searchURL = FeedURL(URL(string: "https://example.com/itunes.rss")!)
    let iTunesID = ITunesPodcastID(200)

    let unsavedPodcast = try Create.unsavedPodcast(
      feedURL: canonicalURL,
      iTunesID: iTunesID,
      title: "Bridged Podcast",
      subscriptionDate: Date()
    )
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: unsavedPodcast)
    )
    let savedPodcast = try await fetchSavedPodcast(series.podcast.id)

    // Simulate what buildUpdatedResult produces for an iTunesID-bridged match
    let wrapper = makeSearchResult(
      resultFeedURL: searchURL,
      originalPodcast: try Create.unsavedPodcast(
        feedURL: searchURL,
        iTunesID: iTunesID,
        title: "Search Result Title"
      ),
      savedPodcast: savedPodcast
    )
    let listed = ListedPodcast(savedSearchResult: wrapper)

    // Row identity stays on the search URL (IdentifiedArray slot stability)
    #expect(listed.id == searchURL)

    // Canonical data flows through for sharing, navigation, DB ops
    #expect(listed.feedURL == canonicalURL)
    #expect(listed.iTunesID == iTunesID)
    #expect(listed.isSaved)
    #expect(listed.subscribed)

    // getOrCreatePodcast() returns the real DB podcast, not a synthetic
    let unwrapped = try await listed.getOrCreatePodcast()
    #expect(unwrapped.id == series.podcast.id)
    #expect(unwrapped.feedURL == canonicalURL)
  }
}
