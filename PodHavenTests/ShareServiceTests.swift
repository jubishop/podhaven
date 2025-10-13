// Copyright Justin Bishop, 2025

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of ShareService tests", .container)
@MainActor class ShareServiceTests {
  @DynamicInjected(\.feedManagerSession) private var feedManagerSession
  @DynamicInjected(\.iTunesServiceSession) private var iTunesServiceSession
  @DynamicInjected(\.navigation) private var navigation
  @DynamicInjected(\.opmlViewModel) private var opmlViewModel
  @DynamicInjected(\.podcastOPMLSession) private var podcastOPMLSession
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.shareService) private var shareService

  var itunesSession: FakeDataFetchable { iTunesServiceSession as! FakeDataFetchable }
  var feedSession: FakeDataFetchable { feedManagerSession as! FakeDataFetchable }
  var opmlSession: FakeDataFetchable { podcastOPMLSession as! FakeDataFetchable }

  @Test("that a new apple podcast URL is correctly imported")
  func newApplePodcastURLImportsSuccessfully() async throws {
    #expect(try await repo.allPodcasts().isEmpty)

    let itunesData = PreviewBundle.loadAsset(named: "lenny", in: .iTunesResults)
    let itunesID: String = "1627920305"
    await itunesSession.respond(
      to: ITunesURL.lookupRequest(podcastIDs: [ITunesPodcastID(Int(itunesID)!)]).url!,
      data: itunesData
    )

    let feedData = PreviewBundle.loadAsset(named: "lenny", in: .FeedRSS)
    let feedURL = URL(string: "https://api.substack.com/feed/podcast/10845.rss")!
    await feedSession.respond(to: feedURL, data: feedData)

    try await shareService.handleIncomingURL(
      ShareHelpers.shareURL(
        with: ShareHelpers.itunesPodcastURL(
          for: itunesID,
          withTitle: "Lenny's Podcast: Product | Growth | Career"
        )
      )
    )

    let podcastSeries = try await repo.podcastSeries(FeedURL(feedURL))!
    #expect(podcastSeries.podcast.subscribed)
    #expect(podcastSeries.podcast.title == "Lenny's Podcast: Product | Growth | Career")
    #expect(podcastSeries.episodes.count == 32)

    #expect(navigation.currentTab == .podcasts)
    #expect(
      navigation.podcasts.path == [
        .podcastsViewType(.subscribed), .podcast(DisplayedPodcast(podcastSeries.podcast)),
      ]
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
        subscriptionDate: subscribed ? Date() : nil
      )
    )
    #expect(try await repo.allPodcasts().count == 1)

    let itunesData = PreviewBundle.loadAsset(named: "lenny", in: .iTunesResults)
    let itunesID: String = "1627920305"
    await itunesSession.respond(
      to: ITunesURL.lookupRequest(podcastIDs: [ITunesPodcastID(Int(itunesID)!)]).url!,
      data: itunesData
    )

    let feedData = PreviewBundle.loadAsset(named: "lenny", in: .FeedRSS)
    await feedSession.respond(to: feedURL, data: feedData)

    try await shareService.handleIncomingURL(
      ShareHelpers.shareURL(
        with: ShareHelpers.itunesPodcastURL(
          for: itunesID,
          withTitle: "Lenny's Podcast: Product | Growth | Career"
        )
      )
    )

    #expect(try await repo.allPodcasts().count == 1)
    let podcastSeries = try await repo.podcastSeries(FeedURL(feedURL))!
    #expect(podcastSeries.podcast.subscribed)
    #expect(podcastSeries.podcast.title == "Lenny's Podcast: Product | Growth | Career")
    #expect(podcastSeries.episodes.count == 32)

    #expect(navigation.currentTab == .podcasts)
    #expect(
      navigation.podcasts.path == [
        .podcastsViewType(.subscribed), .podcast(DisplayedPodcast(podcastSeries.podcast)),
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

  @Test("that ShareError.caught wraps SearchError.fetchFailure when iTunes lookup fails")
  func fetchFailureForITunesLookupRequest() async throws {
    let itunesID = "1234567890"
    let applePodcastsURL = ShareHelpers.itunesPodcastURL(for: itunesID, withTitle: "Test Podcast")
    let shareURL = ShareHelpers.shareURL(with: applePodcastsURL)
    let lookupURL = ITunesURL.lookupRequest(podcastIDs: [ITunesPodcastID(Int(itunesID)!)]).url!

    await itunesSession.respond(to: lookupURL, error: URLError(.networkConnectionLost))

    do {
      try await shareService.handleIncomingURL(shareURL)
      Issue.record("Expected ShareError.caught to be thrown")
    } catch let ShareError.caught(error) {
      guard let searchError = error as? SearchError,
        case .fetchFailure(let request, _) = searchError
      else {
        Issue.record("Expected SearchError.fetchFailure inside ShareError.caught, got: \(error)")
        return
      }
      #expect(request.url == lookupURL)
    } catch {
      Issue.record("Expected ShareError.caught, got: \(error)")
    }
  }

  @Test("that ShareError.caught wraps SearchError.parseFailure for invalid iTunes response")
  func parseFailureForInvalidITunesResponse() async throws {
    let itunesID = "1234567890"
    let applePodcastsURL = ShareHelpers.itunesPodcastURL(for: itunesID, withTitle: "Test Podcast")
    let shareURL = ShareHelpers.shareURL(with: applePodcastsURL)
    let lookupURL = ITunesURL.lookupRequest(podcastIDs: [ITunesPodcastID(Int(itunesID)!)]).url!
    let invalidJSON = "invalid json".data(using: .utf8)!

    await itunesSession.respond(to: lookupURL, data: invalidJSON)

    do {
      try await shareService.handleIncomingURL(shareURL)
      Issue.record("Expected ShareError.caught to be thrown")
    } catch let ShareError.caught(error) {
      guard let searchError = error as? SearchError,
        case .parseFailure(let data, _) = searchError
      else {
        Issue.record("Expected SearchError.parseFailure inside ShareError.caught, got: \(error)")
        return
      }
      #expect(data == invalidJSON)
    } catch {
      Issue.record("Expected ShareError.caught, got: \(error)")
    }
  }

  @Test("that ShareError.noFeedURLFound is thrown when iTunes response has no feed URL")
  func noFeedURLFoundForITunesResponseWithoutFeedURL() async throws {
    let itunesID = "1234567890"
    let applePodcastsURL = ShareHelpers.itunesPodcastURL(for: itunesID, withTitle: "Test Podcast")
    let shareURL = ShareHelpers.shareURL(with: applePodcastsURL)
    let lookupURL = ITunesURL.lookupRequest(podcastIDs: [ITunesPodcastID(Int(itunesID)!)]).url!

    let responseWithoutFeedURL = """
      {
        "resultCount": 1,
        "results": [
          {
            "collectionId": \(itunesID),
            "kind": "podcast"
          }
        ]
      }
      """
      .data(using: .utf8)!

    await itunesSession.respond(to: lookupURL, data: responseWithoutFeedURL)

    await #expect(throws: ShareError.noFeedURLFound) {
      try await self.shareService.handleIncomingURL(shareURL)
    }
  }

  @Test("that ShareError.caught wraps other errors properly")
  func caughtErrorWrapsOtherErrors() async throws {
    let itunesID = "1627920305"
    let applePodcastsURL = ShareHelpers.itunesPodcastURL(for: itunesID, withTitle: "Test Podcast")
    let shareURL = ShareHelpers.shareURL(with: applePodcastsURL)
    let lookupURL = ITunesURL.lookupRequest(podcastIDs: [ITunesPodcastID(Int(itunesID)!)]).url!

    let itunesData = """
      {
        "resultCount": 1,
        "results": [
          {
            "collectionId": \(itunesID),
            "kind": "podcast",
            "feedUrl": "https://api.substack.com/feed/podcast/10845.rss",
            "artworkUrl600": "https://example.com/artwork.jpg"
          }
        ]
      }
      """
      .data(using: .utf8)!

    await itunesSession.respond(to: lookupURL, data: itunesData)

    let feedURL = URL(string: "https://api.substack.com/feed/podcast/10845.rss")!
    await feedSession.respond(to: feedURL, error: URLError(.cannotConnectToHost))

    await #expect(throws: ShareError.caught(URLError(.cannotConnectToHost))) {
      try await self.shareService.handleIncomingURL(shareURL)
    }
  }

  @Test("that episode URL navigates to Podcast")
  func episodeURLNavigatesToPodcast() async throws {
    let feedURL = URL(string: "https://feeds.simplecast.com/7_9d7yco")!
    try await repo.insertSeries(
      Create.unsavedPodcast(
        feedURL: FeedURL(feedURL),
        subscriptionDate: nil
      )
    )

    let podcastID = "1802645201"
    let episodeID = "69420"
    let itunesData = PreviewBundle.loadAsset(named: "dell", in: .iTunesResults)
    await itunesSession.respond(
      to: ITunesURL.lookupRequest(podcastIDs: [ITunesPodcastID(Int(podcastID)!)]).url!,
      data: itunesData
    )

    let feedData = PreviewBundle.loadAsset(named: "dell", in: .FeedRSS)
    await feedSession.respond(to: feedURL, data: feedData)

    try await shareService.handleIncomingURL(
      ShareHelpers.shareURL(
        with: ShareHelpers.itunesEpisodeURL(
          for: podcastID,
          episodeID: episodeID,
          withTitle: "radiance-fields-the-next-leap-in-visualization"
        )
      )
    )

    let podcastSeries = try await repo.podcastSeries(FeedURL(feedURL))!
    #expect(navigation.currentTab == .podcasts)
    #expect(
      navigation.podcasts.path == [
        .podcastsViewType(.subscribed), .podcast(DisplayedPodcast(podcastSeries.podcast)),
      ]
    )
  }

  @Test("that shared OPML file navigates to import view and imports podcasts")
  func sharedOPMLFileImportsSuccessfully() async throws {
    let feedURL = URL(
      string: "https://feeds.soundcloud.com/users/soundcloud:users:122508048/sounds.rss"
    )!
    let feedData = PreviewBundle.loadAsset(named: "techdirt", in: .FeedRSS)
    await feedSession.respond(to: feedURL, data: feedData)

    // Create OPML file URL and data
    let opmlURL = URL(fileURLWithPath: "/tmp/techdirt.OPML")
    let opmlData = PreviewBundle.loadAsset(named: "techdirt", in: .OPML)

    // Set up the fake OPML session to respond to the file URL
    await opmlSession.respond(to: opmlURL, data: opmlData)

    // Write the OPML data to the fake file manager
    let fakeFileManager = Container.shared.podFileManager() as! FakeFileManager
    try await fakeFileManager.writeData(opmlData, to: opmlURL)

    let shareURL = ShareHelpers.shareURL(with: opmlURL)
    try await shareService.handleIncomingURL(shareURL)

    #expect(navigation.currentTab == .settings)
    #expect(navigation.settings.path == [.settingsSection(.opml)])

    let podcastSeries = try await repo.podcastSeries(FeedURL(feedURL))
    #expect(podcastSeries?.podcast.title == "Techdirt")
    #expect(podcastSeries?.podcast.subscriptionDate != nil)
  }

  @Test("that a plain feed URL is imported successfully")
  func plainFeedURLImportsSuccessfully() async throws {
    let feedURL = URL(
      string: "https://changelog.com/podcast/feed"
    )!
    let feedData = PreviewBundle.loadAsset(named: "changelog", in: .FeedRSS)
    await feedSession.respond(to: feedURL, data: feedData)

    try await shareService.handleIncomingURL(ShareHelpers.shareURL(with: feedURL))

    let podcastSeries = try await repo.podcastSeries(FeedURL(feedURL))!
    #expect(podcastSeries.podcast.subscribed)
    #expect(podcastSeries.podcast.title == "The Changelog: Software Development, Open Source")
    #expect(podcastSeries.episodes.count == 835)

    #expect(navigation.currentTab == .podcasts)
    #expect(
      navigation.podcasts.path == [
        .podcastsViewType(.subscribed), .podcast(DisplayedPodcast(podcastSeries.podcast)),
      ]
    )
  }
}
