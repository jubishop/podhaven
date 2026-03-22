// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of SearchResultPodcast tests", .container)
class SearchResultPodcastTests {
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.repo) private var repo

  private func makeSearchResult(
    resultFeedURL: FeedURL,
    originalPodcast: UnsavedPodcast,
    savedPodcast: ListablePodcast,
    originalEpisodeCount: Int = 3,
    originalMostRecentEpisodeDate: Date? = Date(timeIntervalSince1970: 123)
  ) -> SearchResultPodcast {
    SearchResultPodcast(
      resultFeedURL: resultFeedURL,
      originalPodcast: originalPodcast,
      originalEpisodeCount: originalEpisodeCount,
      originalMostRecentEpisodeDate: originalMostRecentEpisodeDate,
      savedPodcast: savedPodcast
    )
  }

  private func fetchSavedPodcast(_ podcastID: Podcast.ID) async throws -> ListablePodcast {
    let results: [PodcastWithEpisodeMetadata<ListablePodcast>] =
      try await observatory.podcastsWithEpisodeMetadata(
        { $0.filter(Podcast.Columns.id == podcastID) },
        limit: 1
      )
      .get()

    return try #require(results.first?.podcast)
  }

  // MARK: - SearchResultPodcast identity

  @Test("id returns resultFeedURL, feedURL returns canonical")
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

    let searchResult = makeSearchResult(
      resultFeedURL: searchURL,
      originalPodcast: try Create.unsavedPodcast(
        feedURL: searchURL,
        iTunesID: ITunesPodcastID(123)
      ),
      savedPodcast: try await fetchSavedPodcast(series.podcast.id)
    )

    #expect(searchResult.id == searchURL)
    #expect(searchResult.feedURL == canonicalURL)
    #expect(searchResult.id != searchResult.feedURL)
  }

  @Test("id equals feedURL when URLs match")
  func testMatchingURLs() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/feed.rss")!)
    let unsavedPodcast = try Create.unsavedPodcast(feedURL: feedURL, title: "Same URL")
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: unsavedPodcast)
    )

    let searchResult = makeSearchResult(
      resultFeedURL: feedURL,
      originalPodcast: try Create.unsavedPodcast(feedURL: feedURL, title: "Same URL"),
      savedPodcast: try await fetchSavedPodcast(series.podcast.id)
    )

    #expect(searchResult.id == searchResult.feedURL)
  }

  @Test("forwards PodcastListable fields from the saved podcast")
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

    let searchResult = makeSearchResult(
      resultFeedURL: FeedURL(URL(string: "https://example.com/search.rss")!),
      originalPodcast: try Create.unsavedPodcast(
        feedURL: FeedURL(URL(string: "https://example.com/search.rss")!),
        iTunesID: iTunesID,
        title: "Original Search Title"
      ),
      savedPodcast: savedPodcast
    )

    #expect(searchResult.title == "Forwarded Title")
    #expect(searchResult.iTunesID == iTunesID)
    #expect(searchResult.isSaved)
    #expect(searchResult.subscribed)
    #expect(searchResult.podcastID == series.podcast.id)
  }

  @Test("preserves the original search metadata for reversion")
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

    let searchResult = makeSearchResult(
      resultFeedURL: originalPodcast.feedURL,
      originalPodcast: originalPodcast,
      savedPodcast: savedPodcast,
      originalEpisodeCount: 7,
      originalMostRecentEpisodeDate: originalDate
    )

    #expect(searchResult.originalPodcast.title == "Original Search Title")
    #expect(searchResult.originalEpisodeCount == 7)
    #expect(searchResult.originalMostRecentEpisodeDate == originalDate)
  }

  // MARK: - ListedPodcast wrapping SearchResultPodcast

  @Test("ListedPodcast.id returns resultFeedURL when wrapping SearchResultPodcast")
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
    let listed = ListedPodcast(searchResult)

    #expect(listed.id == searchURL)
    #expect(listed.feedURL == canonicalURL)
  }

  @Test("ListedPodcast.getOrCreatePodcast() unwraps through SearchResultPodcast")
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
    let listed = ListedPodcast(searchResult)

    let unwrapped = try await listed.getOrCreatePodcast()
    #expect(unwrapped.id == series.podcast.id)
    #expect(unwrapped.feedURL == series.podcast.feedURL)
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
    let listed = ListedPodcast(searchResult)

    let resolved = try await listed.getOrCreatePodcast()
    #expect(resolved.id == series.podcast.id)
    #expect(resolved.feedURL == canonicalURL)
  }

  @Test("ListedPodcast.toOriginalUnsavedPodcast() unwraps through SearchResultPodcast")
  func testToOriginalUnsavedPodcast() async throws {
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
    let listed = ListedPodcast(searchResult)

    let original = try listed.toOriginalUnsavedPodcast()
    #expect(original.feedURL == originalSearchPodcast.feedURL)
    #expect(original.subscriptionDate == nil)
  }

  // MARK: - iTunesID bridge scenario (exercises the same guarantees as buildUpdatedResult)

  @Test("bridged SearchResultPodcast in ListedPodcast preserves all search/trending invariants")
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
    let listed = ListedPodcast(wrapper)

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
