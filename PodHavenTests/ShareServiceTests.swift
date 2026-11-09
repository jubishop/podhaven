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
  @DynamicInjected(\.opmlViewModel) private var opmlViewModel
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.shareService) private var shareService

  var itunesSession: FakeDataFetchable { iTunesServiceSession as! FakeDataFetchable }
  var feedSession: FakeDataFetchable { podcastFeedSession as! FakeDataFetchable }
  var opmlSession: FakeDataFetchable { podcastOPMLSession as! FakeDataFetchable }

  @Test("that a new apple podcast URL is correctly imported")
  func newApplePodcastURLImportsSuccessfully() async throws {
    Container.shared.fakeDate().freeze()
    #expect(try await repo.allPodcasts(AppDB.noOp).isEmpty)

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
    #expect(try await repo.allPodcasts(AppDB.noOp).isEmpty)

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
    #expect(try await repo.allPodcasts(AppDB.noOp).count == 1)

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

    #expect(try await repo.allPodcasts(AppDB.noOp).count == 1)
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

  @Test("that an error is thrown for URLs without url parameter")
  func errorForMissingURLParameter() async throws {
    let shareURL = URL(string: "podhaven://share?invalid=true")!

    await #expect(throws: (any Error).self) {
      try await self.shareService.handleIncomingURL(shareURL)
    }
  }

  @Test("that an error is thrown for URLs with empty url parameter")
  func errorForEmptyURLParameter() async throws {
    let shareURL = URL(string: "podhaven://share?url=")!

    await #expect(throws: (any Error).self) {
      try await self.shareService.handleIncomingURL(shareURL)
    }
  }

  @Test("that an error is thrown for unknown urls")
  func errorForUnknownURLs() async throws {
    let unsupportedURL = URL(string: "https://example.com/podcast")!
    let shareURL = ShareHelpers.shareURL(with: unsupportedURL)

    await #expect(throws: (any Error).self) {
      try await self.shareService.handleIncomingURL(shareURL)
    }
  }

  @Test("that an error is thrown when iTunes lookup fails")
  func errorForITunesLookupFailure() async throws {
    let itunesID = "1234567890"
    let applePodcastsURL = ShareHelpers.itunesPodcastURL(for: itunesID, withTitle: "Test Podcast")
    let shareURL = ShareHelpers.shareURL(with: applePodcastsURL)
    let lookupURL = ITunesURL.lookupRequest(podcastIDs: [ITunesPodcastID(Int(itunesID)!)]).url!

    await itunesSession.respond(to: lookupURL, error: URLError(.networkConnectionLost))

    await #expect(throws: (any Error).self) {
      try await self.shareService.handleIncomingURL(shareURL)
    }
  }

  @Test("that an error is thrown for invalid iTunes response")
  func errorForInvalidITunesResponse() async throws {
    let itunesID = "1234567890"
    let applePodcastsURL = ShareHelpers.itunesPodcastURL(for: itunesID, withTitle: "Test Podcast")
    let shareURL = ShareHelpers.shareURL(with: applePodcastsURL)
    let lookupURL = ITunesURL.lookupRequest(podcastIDs: [ITunesPodcastID(Int(itunesID)!)]).url!
    let invalidJSON = "invalid json".data(using: .utf8)!

    await itunesSession.respond(to: lookupURL, data: invalidJSON)

    await #expect(throws: (any Error).self) {
      try await self.shareService.handleIncomingURL(shareURL)
    }
  }

  @Test("that an error is thrown when feed fetch fails")
  func errorWhenFeedFetchFails() async throws {
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

    await #expect(throws: (any Error).self) {
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

  @Test(
    "that a shared OPML file opens a review and deletes the shared copy",
    arguments: ["OPML", "xml"]
  )
  func sharedOPMLFileOpensReview(fileExtension: String) async throws {
    let feedURL = URL(
      string: "https://feeds.soundcloud.com/users/soundcloud:users:122508048/sounds.rss"
    )!
    let feedData = PreviewBundle.loadAsset(named: "techdirt", in: .FeedRSS)
    await feedSession.respond(to: feedURL, data: feedData)

    let fakeFileManager = Container.shared.fileManager() as! FakeFileManager
    let opmlURL = try sharedContainerURL()
      .appendingPathComponent("shared_file_\(UUID().uuidString).\(fileExtension)")
    let opmlData = PreviewBundle.loadAsset(named: "techdirt", in: .OPML)
    await opmlSession.respond(to: opmlURL, data: opmlData)
    try await fakeFileManager.writeData(opmlData, to: opmlURL)
    #expect(opmlViewModel.opmlFile == nil)

    try await shareService.handleIncomingURL(ShareHelpers.shareURL(with: opmlURL))

    #expect(navigation.currentTab == .settings)
    #expect(navigation.settings.path == [.settingsSection(.opml)])
    #expect(fakeFileManager.removeItemCallCount(for: opmlURL) == 1)

    // The review must present on the injected view model OPMLView renders.
    let opmlFile = try #require(opmlViewModel.opmlFile)
    #expect(opmlFile.phase == .reviewing)
    #expect(opmlFile.waiting.map(\.text) == ["Techdirt"])
    #expect(await feedSession.requests.isEmpty)
    #expect(try await repo.allPodcasts(AppDB.noOp).isEmpty)

    await opmlViewModel.importFeeds()

    let podcastSeries = try await repo.podcastSeries(FeedURL(feedURL))
    #expect(podcastSeries?.podcast.title == "Techdirt")
    #expect(podcastSeries?.podcast.subscriptionDate != nil)
  }

  enum SharedNonOPMLFile: CaseIterable, Sendable {
    case rssFeed, audio

    var fileExtension: String {
      switch self {
      case .rssFeed: "xml"
      case .audio: "mp3"
      }
    }

    var data: Data {
      switch self {
      case .rssFeed: PreviewBundle.loadAsset(named: "techdirt", in: .FeedRSS)
      case .audio: Data([0xFF, 0xFB, 0x90, 0x64, 0x00, 0x00, 0x00, 0x00])
      }
    }
  }

  @Test(
    "that a shared file that is not OPML is rejected and its shared copy deleted",
    arguments: SharedNonOPMLFile.allCases
  )
  func sharedNonOPMLFileIsDeleted(file: SharedNonOPMLFile) async throws {
    let fakeFileManager = Container.shared.fileManager() as! FakeFileManager
    let fileURL = try sharedContainerURL()
      .appendingPathComponent("shared_file_\(UUID().uuidString).\(file.fileExtension)")
    try await fakeFileManager.writeData(file.data, to: fileURL)

    await #expect(throws: URLError.self) {
      try await self.shareService.handleIncomingURL(ShareHelpers.shareURL(with: fileURL))
    }

    #expect(fakeFileManager.removeItemCallCount(for: fileURL) == 1)
    #expect(!fakeFileManager.fileExists(at: fileURL))
    #expect(await opmlSession.requests.isEmpty)
    #expect(await feedSession.requests.isEmpty)
    #expect(opmlViewModel.opmlFile == nil)
    #expect(navigation.settings.path.isEmpty)
    #expect(navigation.search.path.isEmpty)
  }

  @Test("that a remote OPML share URL is rejected without fetching or subscribing")
  func remoteOPMLShareURLIsRejected() async throws {
    let libraryFeedURL = URL(string: "https://api.substack.com/feed/podcast/10845.rss")!
    let libraryPodcast =
      try await repo.insertSeries(
        UnsavedPodcastSeries(
          unsavedPodcast: Create.unsavedPodcast(
            feedURL: FeedURL(libraryFeedURL),
            subscriptionDate: nil
          )
        )
      )
      .podcast
    let newFeedURL = URL(string: "https://feeds.simplecast.com/l2i9YnTd")!
    let newFeedData = PreviewBundle.loadAsset(named: "hardfork_short", in: .FeedRSS)
    await feedSession.respond(to: newFeedURL, data: newFeedData)
    let opmlURL = URL(string: "https://attacker.example/list.opml")!
    await opmlSession.respond(
      to: opmlURL,
      data: Data(
        """
        <?xml version="1.0"?>
        <opml version="1.0">
        <head><title>Planted</title></head>
        <body>
          <outline type="rss" text="Lenny" xmlUrl="\(libraryFeedURL.absoluteString)"/>
          <outline type="rss" text="Hard Fork" xmlUrl="\(newFeedURL.absoluteString)"/>
        </body>
        </opml>
        """
        .utf8
      )
    )

    await #expect(throws: URLError.self) {
      try await self.shareService.handleIncomingURL(ShareHelpers.shareURL(with: opmlURL))
    }

    #expect(await opmlSession.requests.isEmpty)
    #expect(await feedSession.requests.isEmpty)
    #expect(opmlViewModel.opmlFile == nil)
    #expect(try await repo.allPodcasts(AppDB.noOp).map(\.id) == [libraryPodcast.id])
    #expect(try await repo.podcast(libraryPodcast.id)?.subscribed == false)
  }

  enum ForeignOPMLPath: CaseIterable, Sendable {
    case outsideContainer, unprefixedName, subdirectory, parentTraversal

    func url(in container: URL) -> URL {
      switch self {
      case .outsideContainer:
        container.deletingLastPathComponent().appendingPathComponent("shared_file_outside.opml")
      case .unprefixedName:
        container.appendingPathComponent("library.opml")
      case .subdirectory:
        container.appendingPathComponent("Library/shared_file_nested.opml")
      case .parentTraversal:
        URL(string: container.absoluteString + "/../shared_file_escape.opml")!
      }
    }
  }

  @Test(
    "that an OPML file that is not the share extension's copy is neither imported nor deleted",
    arguments: ForeignOPMLPath.allCases
  )
  func foreignOPMLFileIsRejected(path: ForeignOPMLPath) async throws {
    let fakeFileManager = Container.shared.fileManager() as! FakeFileManager
    let fileURL = path.url(in: try sharedContainerURL())
    let opmlData = PreviewBundle.loadAsset(named: "techdirt", in: .OPML)
    try await fakeFileManager.writeData(opmlData, to: fileURL)
    await opmlSession.respond(to: fileURL, data: opmlData)

    await #expect(throws: URLError.self) {
      try await self.shareService.handleIncomingURL(ShareHelpers.shareURL(with: fileURL))
    }

    #expect(fakeFileManager.removeItemCallCount(for: fileURL) == 0)
    #expect(fakeFileManager.removeItemCallCount(for: fileURL.standardizedFileURL) == 0)
    #expect(try await fakeFileManager.readData(from: fileURL) == opmlData)
    #expect(await opmlSession.requests.isEmpty)
    #expect(opmlViewModel.opmlFile == nil)
    #expect(navigation.settings.path.isEmpty)
  }

  @Test(
    "that a share URL with an invalid feed URL is rejected without fetching it",
    arguments: [
      "file:///var/mobile/feed.xml",
      "ftp://example.com/feed.xml",
      "https://artisanalsoftware.com/podhaven/podcast?feedURL=file:///var/mobile/feed.xml",
      "https://www.artisanalsoftware.com/podhaven/episode?feedURL=ftp://example.com/feed.xml&guid=a",
      "https://attacker.example/podhaven/podcast?feedURL=https://example.com/feed.xml",
    ]
  )
  func invalidFeedURLIsRejected(value: String) async throws {
    let feedData = PreviewBundle.loadAsset(named: "changelog", in: .FeedRSS)
    for feedURL in ["file:///var/mobile/feed.xml", "ftp://example.com/feed.xml"] {
      await feedSession.respond(to: URL(string: feedURL)!, data: feedData)
    }

    await #expect(throws: URLError.self) {
      try await self.shareService.handleIncomingURL(
        ShareHelpers.shareURL(with: URL(string: value)!)
      )
    }

    #expect(await feedSession.requests.isEmpty)
    #expect(navigation.search.path.isEmpty)
    #expect(navigation.podcasts.path.isEmpty)
  }

  @Test(
    "that a shared HTTP feed URL is fetched over HTTPS",
    arguments: [false, true]  // wrapped in a PodHaven share link
  )
  func httpFeedURLIsFetchedOverHTTPS(wrapped: Bool) async throws {
    Container.shared.fakeDate().freeze()
    let feedURL = URL(string: "https://changelog.com/podcast/feed")!
    let feedData = PreviewBundle.loadAsset(named: "changelog", in: .FeedRSS)
    await feedSession.respond(to: feedURL, data: feedData)
    let httpFeedURL = "http://changelog.com/podcast/feed"
    let sharedURL =
      wrapped ? ShareHelpers.podcastURL(feedURL: httpFeedURL) : URL(string: httpFeedURL)!

    try await shareService.handleIncomingURL(ShareHelpers.shareURL(with: sharedURL))

    #expect(await feedSession.requests == [feedURL])
    let podcastFeed = try await PodcastFeed.parse(feedData, from: FeedURL(feedURL))
    #expect(navigation.currentTab == .search)
    #expect(navigation.search.path == [.unsavedPodcastSeries(try podcastFeed.toUnsavedSeries())])
  }

  @Test("that a plain feed URL is imported successfully")
  func plainFeedURLImportsSuccessfully() async throws {
    Container.shared.fakeDate().freeze()
    let feedURL = URL(
      string: "https://changelog.com/podcast/feed"
    )!
    let feedData = PreviewBundle.loadAsset(named: "changelog", in: .FeedRSS)
    await feedSession.respond(to: feedURL, data: feedData)

    try await shareService.handleIncomingURL(ShareHelpers.shareURL(with: feedURL))

    // Podcast should NOT be saved to repo
    #expect(try await repo.allPodcasts(AppDB.noOp).isEmpty)

    // Parse feed to get expected unsaved podcast
    let podcastFeed = try await PodcastFeed.parse(feedData, from: FeedURL(feedURL))

    // Should navigate to search tab with unsaved podcast
    #expect(navigation.currentTab == .search)
    #expect(navigation.search.path == [.unsavedPodcastSeries(try podcastFeed.toUnsavedSeries())])
  }

  @Test("that a new episode URL with feedURL and guid navigates to specific episode")
  func newEpisodeURLWithGUIDNavigatesToEpisode() async throws {
    Container.shared.fakeDate().freeze()
    #expect(try await repo.allPodcasts(AppDB.noOp).isEmpty)

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
    #expect(try await repo.allPodcasts(AppDB.noOp).isEmpty)

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
    #expect(try await repo.allPodcasts(AppDB.noOp).count == 1)

    await feedSession.respond(to: feedURL, data: feedData)

    let episodeGUID = "substack:post:167485876"  // Second episode in the feed
    let episodeURL = ShareHelpers.episodeURL(
      feedURL: feedURL.absoluteString,
      guid: episodeGUID
    )

    try await shareService.handleIncomingURL(ShareHelpers.shareURL(with: episodeURL))

    // Should still have only one podcast
    #expect(try await repo.allPodcasts(AppDB.noOp).count == 1)

    // Verify navigation goes to the specific episode
    #expect(navigation.currentTab == .podcasts)
    #expect(navigation.podcasts.path.count == 3)

    guard case .episode(let displayedEpisode, _) = navigation.podcasts.path[safe: 2] else {
      Issue.record("Expected navigation to episode, but got: \(navigation.podcasts.path[safe: 2])")
      return
    }
    #expect(displayedEpisode.mediaGUID.guid.rawValue == episodeGUID)
    #expect(displayedEpisode.title.contains("Foundation Sprint"))
  }

  @Test("that an episode URL with invalid guid falls back to podcast")
  func episodeURLWithInvalidGUIDFallsBackToPodcast() async throws {
    Container.shared.fakeDate().freeze()
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
    #expect(try await repo.allPodcasts(AppDB.noOp).isEmpty)

    // Parse feed to get expected unsaved podcast
    let podcastFeed = try await PodcastFeed.parse(feedData, from: FeedURL(feedURL))

    // Verify navigation falls back to podcast (not episode)
    #expect(navigation.currentTab == .search)
    #expect(navigation.search.path == [.unsavedPodcastSeries(try podcastFeed.toUnsavedSeries())])
  }

  @Test("that an episode URL with startTime passes startTime through to navigation")
  func episodeURLWithStartTimePassesThrough() async throws {
    let feedURL = URL(string: "https://api.substack.com/feed/podcast/10845.rss")!
    let feedData = PreviewBundle.loadAsset(named: "lenny", in: .FeedRSS)

    // Pre-populate the database with the podcast
    let podcastFeed = try await PodcastFeed.parse(feedData, from: FeedURL(feedURL))
    try await repo.insertSeries(podcastFeed.toUnsavedSeries())

    await feedSession.respond(to: feedURL, data: feedData)

    let episodeGUID = "substack:post:167485876"
    let episodeURL = ShareHelpers.episodeURL(
      feedURL: feedURL.absoluteString,
      guid: episodeGUID,
      startTime: 90
    )

    try await shareService.handleIncomingURL(ShareHelpers.shareURL(with: episodeURL))

    #expect(navigation.currentTab == .podcasts)
    guard case .episode(_, let startTime) = navigation.podcasts.path[safe: 2] else {
      Issue.record("Expected navigation to episode")
      return
    }
    #expect(startTime == 90)
  }

  @Test("that an episode URL with negative startTime ignores startTime")
  func episodeURLWithNegativeStartTimeIgnoresIt() async throws {
    let feedURL = URL(string: "https://api.substack.com/feed/podcast/10845.rss")!
    let feedData = PreviewBundle.loadAsset(named: "lenny", in: .FeedRSS)

    let podcastFeed = try await PodcastFeed.parse(feedData, from: FeedURL(feedURL))
    try await repo.insertSeries(podcastFeed.toUnsavedSeries())

    await feedSession.respond(to: feedURL, data: feedData)

    let episodeGUID = "substack:post:167485876"
    // Manually construct URL with negative startTime
    var components = URLComponents(string: "https://www.artisanalsoftware.com/podhaven/episode")!
    components.queryItems = [
      URLQueryItem(name: "feedURL", value: feedURL.absoluteString),
      URLQueryItem(name: "guid", value: episodeGUID),
      URLQueryItem(name: "startTime", value: "-5"),
    ]

    try await shareService.handleIncomingURL(ShareHelpers.shareURL(with: components.url!))

    guard case .episode(_, let startTime) = navigation.podcasts.path[safe: 2] else {
      Issue.record("Expected navigation to episode")
      return
    }
    #expect(startTime == nil)
  }

  @Test("that a podcast URL with only feedURL (no guid) navigates to podcast")
  func podcastURLWithoutGUIDNavigatesToPodcast() async throws {
    Container.shared.fakeDate().freeze()
    let feedURL = URL(string: "https://api.substack.com/feed/podcast/10845.rss")!
    let feedData = PreviewBundle.loadAsset(named: "lenny", in: .FeedRSS)
    await feedSession.respond(to: feedURL, data: feedData)

    let podcastURL = ShareHelpers.podcastURL(feedURL: feedURL.absoluteString)

    try await shareService.handleIncomingURL(ShareHelpers.shareURL(with: podcastURL))

    // Podcast should NOT be saved to repo
    #expect(try await repo.allPodcasts(AppDB.noOp).isEmpty)

    // Parse feed to get expected unsaved podcast
    let podcastFeed = try await PodcastFeed.parse(feedData, from: FeedURL(feedURL))

    // Verify navigation goes to search tab with unsaved podcast
    #expect(navigation.currentTab == .search)
    #expect(navigation.search.path == [.unsavedPodcastSeries(try podcastFeed.toUnsavedSeries())])
  }

  // MARK: - Helpers

  private func sharedContainerURL() throws -> URL {
    try #require(
      Container.shared.fileManager()
        .containerURL(forSecurityApplicationGroupIdentifier: AppInfo.appGroupID)
    )
  }
}
