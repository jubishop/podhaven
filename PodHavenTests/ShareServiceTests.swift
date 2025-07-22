// Copyright Justin Bishop, 2025

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of ShareService tests", .container)
@MainActor class ShareServiceTests {
  @DynamicInjected(\.feedManagerSession) private var feedManagerSession
  @DynamicInjected(\.navigation) private var navigation
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.shareServiceSession) private var shareServiceSession
  @DynamicInjected(\.shareService) private var shareService

  var shareSession: FakeDataFetchable { shareServiceSession as! FakeDataFetchable }
  var feedSession: FakeDataFetchable { feedManagerSession as! FakeDataFetchable }

  @Test("that a new apple podcast URL is correctly imported")
  func newApplePodcastURLImportsSuccessfully() async throws {
    #expect(try await repo.allPodcasts().isEmpty)

    let itunesData = try Data(
      contentsOf: Bundle.main.url(forResource: "lenny", withExtension: "json")!
    )
    let itunesID: String = "1627920305"
    await shareSession.respond(
      to: ShareHelpers.itunesLookupURL(for: itunesID),
      data: itunesData
    )

    let feedData = try Data(
      contentsOf: Bundle.main.url(forResource: "lenny", withExtension: "rss")!
    )
    let feedURL = URL(string: "https://api.substack.com/feed/podcast/10845.rss")!
    await feedSession.respond(to: feedURL, data: feedData)

    try await shareService.handleIncomingURL(
      ShareHelpers.shareURL(
        with: ShareHelpers.itunesURL(
          for: itunesID,
          withTitle: "Lenny's Podcast: Product | Growth | Career"
        )
      )
    )

    let podcastSeries = try await repo.podcastSeries(FeedURL(feedURL))!
    #expect(!podcastSeries.podcast.subscribed)
    #expect(podcastSeries.podcast.title == "Lenny's Podcast: Product | Growth | Career")
    #expect(podcastSeries.episodes.count == 32)

    #expect(navigation.currentTab == .podcasts)
    #expect(
      navigation.podcasts.path == [.viewType(.unsubscribed), .podcast(podcastSeries.podcast)]
    )
  }

  @Test(
    "that an existing apple podcast URL is shown correctly",
    arguments: [false, true]  // podcast.subscribed
  )
  func existingApplePodcastURLShowsSuccessfully(subscribed: Bool) async throws {
    let feedURL = URL(string: "https://api.substack.com/feed/podcast/10845.rss")!
    try await repo.insertSeries(
      Create.unsavedPodcast(
        feedURL: FeedURL(feedURL),
        subscribed: subscribed
      )
    )
    #expect(try await repo.allPodcasts().count == 1)

    let itunesData = try Data(
      contentsOf: Bundle.main.url(forResource: "lenny", withExtension: "json")!
    )
    let itunesID: String = "1627920305"
    await shareSession.respond(
      to: ShareHelpers.itunesLookupURL(for: itunesID),
      data: itunesData
    )

    let feedData = try Data(
      contentsOf: Bundle.main.url(forResource: "lenny", withExtension: "rss")!
    )
    await feedSession.respond(to: feedURL, data: feedData)

    try await shareService.handleIncomingURL(
      ShareHelpers.shareURL(
        with: ShareHelpers.itunesURL(
          for: itunesID,
          withTitle: "Lenny's Podcast: Product | Growth | Career"
        )
      )
    )

    #expect(try await repo.allPodcasts().count == 1)
    let podcastSeries = try await repo.podcastSeries(FeedURL(feedURL))!
    #expect(podcastSeries.podcast.subscribed == subscribed)
    #expect(podcastSeries.podcast.title == "Lenny's Podcast: Product | Growth | Career")
    #expect(podcastSeries.episodes.count == 32)

    #expect(navigation.currentTab == .podcasts)
    #expect(
      navigation.podcasts.path == [
        .viewType(subscribed ? .subscribed : .unsubscribed), .podcast(podcastSeries.podcast),
      ]
    )
  }

  @Test("that ShareError.extractionFailure is thrown for URLs without url parameter")
  func extractionFailureForMissingURLParameter() async throws {
    let shareURL = URL(string: "podhaven://share?invalid=true")!

    await #expect(throws: ShareError.extractionFailure(shareURL)) {
      try await self.shareService.handleIncomingURL(shareURL)
    }
  }

  @Test("that ShareError.extractionFailure is thrown for URLs with empty url parameter")
  func extractionFailureForEmptyURLParameter() async throws {
    let shareURL = URL(string: "podhaven://share?url=")!

    await #expect(throws: ShareError.extractionFailure(shareURL)) {
      try await self.shareService.handleIncomingURL(shareURL)
    }
  }

  @Test("that ShareError.unsupportedURL is thrown for unknown urls")
  func unsupportedURLForUnknownURLs() async throws {
    let unsupportedURL = URL(string: "https://example.com/podcast")!
    let shareURL = ShareHelpers.shareURL(with: unsupportedURL)

    await #expect(throws: ShareError.unsupportedURL(unsupportedURL)) {
      try await self.shareService.handleIncomingURL(shareURL)
    }
  }

  @Test("that ShareError.noIdentifierFound is thrown for Apple Podcasts URLs without ID")
  func noIdentifierFoundForApplePodcastsURLWithoutID() async throws {
    let applePodcastsURL = URL(string: "https://podcasts.apple.com/us/podcast/podcast-name")!
    let shareURL = ShareHelpers.shareURL(with: applePodcastsURL)

    await #expect(throws: ShareError.noIdentifierFound(applePodcastsURL)) {
      try await self.shareService.handleIncomingURL(shareURL)
    }
  }

  @Test("that ShareError.fetchFailure is thrown when iTunes lookup request fails")
  func fetchFailureForITunesLookupRequest() async throws {
    let itunesID = "1234567890"
    let applePodcastsURL = ShareHelpers.itunesURL(for: itunesID, withTitle: "Test Podcast")
    let shareURL = ShareHelpers.shareURL(with: applePodcastsURL)
    let lookupURL = ShareHelpers.itunesLookupURL(for: itunesID)

    await shareSession.respond(to: lookupURL, error: URLError(.networkConnectionLost))

    await #expect(
      throws: ShareError.fetchFailure(
        request: URLRequest(url: lookupURL),
        caught: URLError(.networkConnectionLost)
      )
    ) {
      try await self.shareService.handleIncomingURL(shareURL)
    }
  }

  @Test("that ShareError.parseFailure is thrown for invalid iTunes response JSON")
  func parseFailureForInvalidITunesResponse() async throws {
    let itunesID = "1234567890"
    let applePodcastsURL = ShareHelpers.itunesURL(for: itunesID, withTitle: "Test Podcast")
    let shareURL = ShareHelpers.shareURL(with: applePodcastsURL)
    let lookupURL = ShareHelpers.itunesLookupURL(for: itunesID)
    let invalidJSON = "invalid json".data(using: .utf8)!

    await shareSession.respond(to: lookupURL, data: invalidJSON)

    await #expect(throws: ShareError.parseFailure(invalidJSON)) {
      try await self.shareService.handleIncomingURL(shareURL)
    }
  }

  @Test("that ShareError.noFeedURLFound is thrown when iTunes response has no feed URL")
  func noFeedURLFoundForITunesResponseWithoutFeedURL() async throws {
    let itunesID = "1234567890"
    let applePodcastsURL = ShareHelpers.itunesURL(for: itunesID, withTitle: "Test Podcast")
    let shareURL = ShareHelpers.shareURL(with: applePodcastsURL)
    let lookupURL = ShareHelpers.itunesLookupURL(for: itunesID)

    let responseWithoutFeedURL = """
      {
        "resultCount": 1,
        "results": [
          {
            "trackId": \(itunesID),
            "kind": "podcast"
          }
        ]
      }
      """
      .data(using: .utf8)!

    await shareSession.respond(to: lookupURL, data: responseWithoutFeedURL)

    await #expect(throws: ShareError.noFeedURLFound) {
      try await self.shareService.handleIncomingURL(shareURL)
    }
  }

  @Test("that ShareError.caught wraps other errors properly")
  func caughtErrorWrapsOtherErrors() async throws {
    let itunesID = "1627920305"
    let applePodcastsURL = ShareHelpers.itunesURL(for: itunesID, withTitle: "Test Podcast")
    let shareURL = ShareHelpers.shareURL(with: applePodcastsURL)
    let lookupURL = ShareHelpers.itunesLookupURL(for: itunesID)

    let itunesData = """
      {
        "resultCount": 1,
        "results": [
          {
            "trackId": \(itunesID),
            "kind": "podcast",
            "feedUrl": "https://api.substack.com/feed/podcast/10845.rss"
          }
        ]
      }
      """
      .data(using: .utf8)!

    await shareSession.respond(to: lookupURL, data: itunesData)

    let feedURL = URL(string: "https://api.substack.com/feed/podcast/10845.rss")!
    await feedSession.respond(to: feedURL, error: URLError(.cannotConnectToHost))

    await #expect(throws: ShareError.caught(URLError(.cannotConnectToHost))) {
      try await self.shareService.handleIncomingURL(shareURL)
    }
  }
}
