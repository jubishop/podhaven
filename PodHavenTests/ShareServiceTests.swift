// Copyright Justin Bishop, 2025

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of ShareService tests", .container)
@MainActor class ShareServiceTests {
  @DynamicInjected(\.iTunesServiceSession) private var iTunesServiceSession
  @DynamicInjected(\.navigation) private var navigation
  @DynamicInjected(\.podcastFeedSession) private var podcastFeedSession
  @DynamicInjected(\.podcastOPMLSession) private var podcastOPMLSession
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.shareService) private var shareService

  var itunesSession: FakeDataFetchable { iTunesServiceSession as! FakeDataFetchable }
  var feedSession: FakeDataFetchable { podcastFeedSession as! FakeDataFetchable }
  var opmlSession: FakeDataFetchable { podcastOPMLSession as! FakeDataFetchable }

  @Test("that a new apple podcast URL is correctly imported")
  func newApplePodcastURLImportsSuccessfully() async throws {
    #expect(try await repo.allPodcasts(AppDB.NoOp).isEmpty)

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

    // Podcast should NOT be saved to repo
    #expect(try await repo.allPodcasts(AppDB.NoOp).isEmpty)

    // Parse feed to get expected unsaved podcast
    let podcastFeed = try await PodcastFeed.parse(feedData, from: FeedURL(feedURL))

    // Should navigate to search tab with unsaved podcast
    #expect(navigation.currentTab == .search)
    #expect(navigation.search.path == [.unsavedPodcastSeries(try podcastFeed.toUnsavedSeries())])
  }

  @Test(
    "that an existing apple podcast URL is shown correctly",
    arguments: [false, true]  // podcast.subscribed
  )
  func existingApplePodcastURLShowsSuccessfully(subscribed: Bool) async throws {
    let feedURL = URL(string: "https://api.substack.com/feed/podcast/10845.rss")!
    let feedData = PreviewBundle.loadAsset(named: "lenny", in: .FeedRSS)

    // Pre-populate the database with the podcast and episodes
    let podcastFeed = try await PodcastFeed.parse(feedData, from: FeedURL(feedURL))
    let unsavedPodcast = try podcastFeed.toUnsavedPodcast()
    let insertedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: podcastFeed.toUnsavedEpisodes()
      )
    )
    if subscribed {
      try await repo.markSubscribed(insertedSeries.id)
    }
    #expect(try await repo.allPodcasts(AppDB.NoOp).count == 1)

    let itunesData = PreviewBundle.loadAsset(named: "lenny", in: .iTunesResults)
    let itunesID: String = "1627920305"
    await itunesSession.respond(
      to: ITunesURL.lookupRequest(podcastIDs: [ITunesPodcastID(Int(itunesID)!)]).url!,
      data: itunesData
    )

    await feedSession.respond(to: feedURL, data: feedData)

    try await shareService.handleIncomingURL(
      ShareHelpers.shareURL(
        with: ShareHelpers.itunesPodcastURL(
          for: itunesID,
          withTitle: "Lenny's Podcast: Product | Growth | Career"
        )
      )
    )

    #expect(try await repo.allPodcasts(AppDB.NoOp).count == 1)
    let podcastSeries = try await repo.podcastSeries(FeedURL(feedURL))!
    #expect(podcastSeries.podcast.subscribed == subscribed)
    #expect(podcastSeries.podcast.title == "Lenny's Podcast: Product | Growth | Career")
    #expect(podcastSeries.episodes.count == 32)

    #expect(navigation.currentTab == .podcasts)
    #expect(
      navigation.podcasts.path == [
        .podcastsViewType(subscribed ? .subscribed : .unsubscribed),
        .podcast(DisplayedPodcast(podcastSeries.podcast)),
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
      UnsavedPodcastSeries(
        unsavedPodcast: Create.unsavedPodcast(
          feedURL: FeedURL(feedURL),
          subscriptionDate: nil
        )
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
        .podcastsViewType(.unsubscribed), .podcast(DisplayedPodcast(podcastSeries.podcast)),
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
    let fakeFileManager = Container.shared.fileManager() as! FakeFileManager
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

    // Podcast should NOT be saved to repo
    #expect(try await repo.allPodcasts(AppDB.NoOp).isEmpty)

    // Parse feed to get expected unsaved podcast
    let podcastFeed = try await PodcastFeed.parse(feedData, from: FeedURL(feedURL))

    // Should navigate to search tab with unsaved podcast
    #expect(navigation.currentTab == .search)
    #expect(navigation.search.path == [.unsavedPodcastSeries(try podcastFeed.toUnsavedSeries())])
  }

  @Test("that a new episode URL with feedURL and guid navigates to specific episode")
  func newEpisodeURLWithGUIDNavigatesToEpisode() async throws {
    #expect(try await repo.allPodcasts(AppDB.NoOp).isEmpty)

    let feedURL = URL(string: "https://api.substack.com/feed/podcast/10845.rss")!
    let feedData = PreviewBundle.loadAsset(named: "lenny", in: .FeedRSS)
    await feedSession.respond(to: feedURL, data: feedData)

    let episodeGUID = "substack:post:167681269"
    let episodeURL = ShareHelpers.episodeURL(
      feedURL: feedURL.absoluteString,
      guid: episodeGUID
    )

    try await shareService.handleIncomingURL(ShareHelpers.shareURL(with: episodeURL))

    // Podcast should NOT be saved to repo
    #expect(try await repo.allPodcasts(AppDB.NoOp).isEmpty)

    // Parse feed to get expected unsaved podcast and episode
    let podcastFeed = try await PodcastFeed.parse(feedData, from: FeedURL(feedURL))
    let expectedUnsavedPodcast = try podcastFeed.toUnsavedPodcast()
    let unsavedEpisodes = podcastFeed.toUnsavedEpisodes()
    let expectedUnsavedEpisode = unsavedEpisodes.first {
      $0.mediaGUID.guid.rawValue == episodeGUID
    }!
    let expectedUnsavedPodcastEpisode = UnsavedPodcastEpisode(
      unsavedPodcast: expectedUnsavedPodcast,
      unsavedEpisode: expectedUnsavedEpisode
    )

    // Should navigate to search tab with unsaved episode
    #expect(navigation.currentTab == .search)
    #expect(
      navigation.search.path == [
        .unsavedPodcastSeries(try podcastFeed.toUnsavedSeries()),
        .episode(DisplayedEpisode(expectedUnsavedPodcastEpisode)),
      ]
    )
  }

  @Test("that an existing episode URL with feedURL and guid navigates to specific episode")
  func existingEpisodeURLWithGUIDNavigatesToEpisode() async throws {
    let feedURL = URL(string: "https://api.substack.com/feed/podcast/10845.rss")!
    let feedData = PreviewBundle.loadAsset(named: "lenny", in: .FeedRSS)

    // Pre-populate the database with the podcast
    let podcastFeed = try await PodcastFeed.parse(feedData, from: FeedURL(feedURL))
    try await repo.insertSeries(podcastFeed.toUnsavedSeries())
    #expect(try await repo.allPodcasts(AppDB.NoOp).count == 1)

    await feedSession.respond(to: feedURL, data: feedData)

    let episodeGUID = "substack:post:167485876"  // Second episode in the feed
    let episodeURL = ShareHelpers.episodeURL(
      feedURL: feedURL.absoluteString,
      guid: episodeGUID
    )

    try await shareService.handleIncomingURL(ShareHelpers.shareURL(with: episodeURL))

    // Should still have only one podcast
    #expect(try await repo.allPodcasts(AppDB.NoOp).count == 1)

    // Verify navigation goes to the specific episode
    #expect(navigation.currentTab == .podcasts)
    #expect(navigation.podcasts.path.count == 3)

    guard case .episode(let displayedEpisode) = navigation.podcasts.path[safe: 2] else {
      Issue.record("Expected navigation to episode, but got: \(navigation.podcasts.path[safe: 2])")
      return
    }
    #expect(displayedEpisode.episode.mediaGUID.guid.rawValue == episodeGUID)
    #expect(displayedEpisode.episode.title.contains("Foundation Sprint"))
  }

  @Test("that an episode URL with invalid guid falls back to podcast")
  func episodeURLWithInvalidGUIDFallsBackToPodcast() async throws {
    let feedURL = URL(string: "https://api.substack.com/feed/podcast/10845.rss")!
    let feedData = PreviewBundle.loadAsset(named: "lenny", in: .FeedRSS)
    await feedSession.respond(to: feedURL, data: feedData)

    let invalidGUID = "nonexistent-guid-12345"
    let episodeURL = ShareHelpers.episodeURL(
      feedURL: feedURL.absoluteString,
      guid: invalidGUID
    )

    try await shareService.handleIncomingURL(ShareHelpers.shareURL(with: episodeURL))

    // Podcast should NOT be saved to repo
    #expect(try await repo.allPodcasts(AppDB.NoOp).isEmpty)

    // Parse feed to get expected unsaved podcast
    let podcastFeed = try await PodcastFeed.parse(feedData, from: FeedURL(feedURL))

    // Verify navigation falls back to podcast (not episode)
    #expect(navigation.currentTab == .search)
    #expect(navigation.search.path == [.unsavedPodcastSeries(try podcastFeed.toUnsavedSeries())])
  }

  @Test("that a podcast URL with only feedURL (no guid) navigates to podcast")
  func podcastURLWithoutGUIDNavigatesToPodcast() async throws {
    let feedURL = URL(string: "https://api.substack.com/feed/podcast/10845.rss")!
    let feedData = PreviewBundle.loadAsset(named: "lenny", in: .FeedRSS)
    await feedSession.respond(to: feedURL, data: feedData)

    let podcastURL = ShareHelpers.podcastURL(feedURL: feedURL.absoluteString)

    try await shareService.handleIncomingURL(ShareHelpers.shareURL(with: podcastURL))

    // Podcast should NOT be saved to repo
    #expect(try await repo.allPodcasts(AppDB.NoOp).isEmpty)

    // Parse feed to get expected unsaved podcast
    let podcastFeed = try await PodcastFeed.parse(feedData, from: FeedURL(feedURL))

    // Verify navigation goes to search tab with unsaved podcast
    #expect(navigation.currentTab == .search)
    #expect(navigation.search.path == [.unsavedPodcastSeries(try podcastFeed.toUnsavedSeries())])
  }
}
