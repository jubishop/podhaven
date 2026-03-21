// Copyright Justin Bishop, 2025

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of SearchResultPodcast tests", .container)
class SearchResultPodcastTests {
  @DynamicInjected(\.repo) private var repo

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

    let searchResult = SearchResultPodcast(
      resultFeedURL: searchURL,
      podcast: series.podcast
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

    let searchResult = SearchResultPodcast(
      resultFeedURL: feedURL,
      podcast: series.podcast
    )

    #expect(searchResult.id == searchResult.feedURL)
  }

  @Test("forwards PodcastDisplayable fields from wrapped podcast")
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

    let searchResult = SearchResultPodcast(
      resultFeedURL: FeedURL(URL(string: "https://example.com/search.rss")!),
      podcast: series.podcast
    )

    #expect(searchResult.title == "Forwarded Title")
    #expect(searchResult.iTunesID == iTunesID)
    #expect(searchResult.isSaved)
    #expect(searchResult.subscribed)
    #expect(searchResult.podcastID == series.podcast.id)
  }

  // MARK: - DisplayedPodcast wrapping SearchResultPodcast

  @Test("DisplayedPodcast.id returns resultFeedURL when wrapping SearchResultPodcast")
  func testDisplayedPodcastId() async throws {
    let canonicalURL = FeedURL(URL(string: "https://example.com/canonical.rss")!)
    let searchURL = FeedURL(URL(string: "https://example.com/search.rss")!)
    let unsavedPodcast = try Create.unsavedPodcast(feedURL: canonicalURL)
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: unsavedPodcast)
    )

    let searchResult = SearchResultPodcast(
      resultFeedURL: searchURL,
      podcast: series.podcast
    )
    let displayed = DisplayedPodcast(searchResult)

    #expect(displayed.id == searchURL)
    #expect(displayed.feedURL == canonicalURL)
  }

  @Test("DisplayedPodcast.getPodcast() unwraps through SearchResultPodcast")
  func testGetPodcastUnwrap() async throws {
    let unsavedPodcast = try Create.unsavedPodcast(title: "Unwrap Test")
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: unsavedPodcast)
    )

    let searchResult = SearchResultPodcast(
      resultFeedURL: FeedURL(URL(string: "https://example.com/search.rss")!),
      podcast: series.podcast
    )
    let displayed = DisplayedPodcast(searchResult)

    let unwrapped = displayed.getPodcast()
    #expect(unwrapped != nil)
    #expect(unwrapped?.id == series.podcast.id)
    #expect(unwrapped?.feedURL == series.podcast.feedURL)
  }

  @Test("DisplayedPodcast.getOrCreatePodcast() returns the real Podcast")
  func testGetOrCreatePodcast() async throws {
    let canonicalURL = FeedURL(URL(string: "https://example.com/canonical.rss")!)
    let unsavedPodcast = try Create.unsavedPodcast(
      feedURL: canonicalURL,
      title: "Real Podcast"
    )
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: unsavedPodcast)
    )

    let searchResult = SearchResultPodcast(
      resultFeedURL: FeedURL(URL(string: "https://example.com/search.rss")!),
      podcast: series.podcast
    )
    let displayed = DisplayedPodcast(searchResult)

    let resolved = try await displayed.getOrCreatePodcast()
    #expect(resolved.id == series.podcast.id)
    #expect(resolved.feedURL == canonicalURL)
  }

  @Test("DisplayedPodcast.toOriginalUnsavedPodcast() unwraps through SearchResultPodcast")
  func testToOriginalUnsavedPodcast() async throws {
    let canonicalURL = FeedURL(URL(string: "https://example.com/canonical.rss")!)
    let unsavedPodcast = try Create.unsavedPodcast(
      feedURL: canonicalURL,
      subscriptionDate: Date()
    )
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: unsavedPodcast)
    )

    let searchResult = SearchResultPodcast(
      resultFeedURL: FeedURL(URL(string: "https://example.com/search.rss")!),
      podcast: series.podcast
    )
    let displayed = DisplayedPodcast(searchResult)

    let original = try displayed.toOriginalUnsavedPodcast()
    #expect(original.feedURL == canonicalURL)
    #expect(original.subscriptionDate == nil)
  }

  // MARK: - iTunesID bridge scenario (exercises the same guarantees as buildUpdatedResult)

  @Test("bridged SearchResultPodcast in DisplayedPodcast preserves all search/trending invariants")
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

    // Simulate what buildUpdatedResult produces for an iTunesID-bridged match
    let wrapper = SearchResultPodcast(
      resultFeedURL: searchURL,
      podcast: series.podcast
    )
    let displayed = DisplayedPodcast(wrapper)

    // Row identity stays on the search URL (IdentifiedArray slot stability)
    #expect(displayed.id == searchURL)

    // Canonical data flows through for sharing, navigation, DB ops
    #expect(displayed.feedURL == canonicalURL)
    #expect(displayed.iTunesID == iTunesID)
    #expect(displayed.isSaved)
    #expect(displayed.subscribed)

    // getPodcast() returns the real DB podcast, not a synthetic
    let unwrapped = displayed.getPodcast()
    #expect(unwrapped?.id == series.podcast.id)
    #expect(unwrapped?.feedURL == canonicalURL)
  }
}
