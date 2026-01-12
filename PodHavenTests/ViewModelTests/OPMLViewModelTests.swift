// Copyright Justin Bishop, 2025

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of OPMLViewModel tests", .container)
@MainActor class OPMLViewModelTests {
  @DynamicInjected(\.podcastFeedSession) private var podcastFeedSession
  @DynamicInjected(\.podcastOPMLSession) private var podcastOPMLSession
  @DynamicInjected(\.repo) private var repo

  var feedSession: FakeDataFetchable { podcastFeedSession as! FakeDataFetchable }
  var opmlSession: FakeDataFetchable { podcastOPMLSession as! FakeDataFetchable }

  let opmlViewModel = OPMLViewModel()

  // MARK: - Tests

  @Test("importing OPML with all valid feeds")
  func importOPMLWithValidFeeds() async throws {
    // Setup: Create OPML with 3 valid feeds
    let feed1URL = URL(string: "https://api.substack.com/feed/podcast/10845.rss")!
    let feed2URL = URL(string: "https://feeds.simplecast.com/l2i9YnTd")!
    let feed3URL = URL(string: "https://www.marketplace.org/feed/podcast/marketplace")!

    let opmlURL = createTestOPMLURL()
    await setupOPMLResponse(
      to: opmlURL,
      feeds: [
        (title: "Lenny's Podcast", url: feed1URL.absoluteString),
        (title: "Hard Fork", url: feed2URL.absoluteString),
        (title: "Marketplace", url: feed3URL.absoluteString),
      ]
    )

    await setupValidFeedResponse(to: feed1URL, assetName: "lenny")
    await setupValidFeedResponse(to: feed2URL, assetName: "hardfork_short")
    await setupValidFeedResponse(to: feed3URL, assetName: "marketplace")

    // Verify initial state
    #expect(try await repo.allPodcasts(AppDB.NoOp).isEmpty)
    #expect(opmlViewModel.opmlFile == nil)

    // Execute and wait for completion
    _ = try await importOPML(from: opmlURL)
    try await waitForAllComplete()

    // Verify OPMLFile state
    try await verifyOPMLFileState(
      title: "Test OPML Subscriptions",
      totalCount: 3,
      waiting: 0,
      downloading: 0,
      finished: 3,
      failed: 0
    )

    // Verify podcasts were saved to repo
    try await verifyPodcastsInRepo(
      expectedCount: 3,
      feedURLs: [
        feed1URL.absoluteString,
        feed2URL.absoluteString,
        feed3URL.absoluteString,
      ]
    )
  }

  @Test("importing OPML with some malformed feeds")
  func importOPMLWithMalformedFeeds() async throws {
    // Setup: Create OPML with 4 feeds, 2 valid and 2 malformed
    let validFeed1URL = URL(string: "https://api.substack.com/feed/podcast/10845.rss")!
    let malformedFeed1URL = URL(string: "https://feeds.invalid.com/malformed1")!
    let validFeed2URL = URL(string: "https://feeds.simplecast.com/l2i9YnTd")!
    let malformedFeed2URL = URL(string: "https://feeds.invalid.com/malformed2")!

    let opmlURL = createTestOPMLURL()
    await setupOPMLResponse(
      to: opmlURL,
      feeds: [
        (title: "Lenny's Podcast", url: validFeed1URL.absoluteString),
        (title: "Malformed Feed 1", url: malformedFeed1URL.absoluteString),
        (title: "Hard Fork", url: validFeed2URL.absoluteString),
        (title: "Malformed Feed 2", url: malformedFeed2URL.absoluteString),
      ]
    )

    await setupValidFeedResponse(to: validFeed1URL, assetName: "lenny")
    await setupValidFeedResponse(to: validFeed2URL, assetName: "hardfork_short")
    await setupMalformedFeedResponse(to: malformedFeed1URL)
    await setupMalformedFeedResponse(to: malformedFeed2URL)

    // Verify initial state
    #expect(try await repo.allPodcasts(AppDB.NoOp).isEmpty)

    // Execute and wait for completion
    try await importOPML(from: opmlURL)
    try await waitForAllComplete()

    // Verify final state: 2 finished, 2 failed
    try await verifyOPMLFileState(
      totalCount: 4,
      finished: 2,
      failed: 2
    )

    // Verify only valid podcasts were saved to repo
    try await verifyPodcastsInRepo(
      expectedCount: 2,
      feedURLs: [
        validFeed1URL.absoluteString,
        validFeed2URL.absoluteString,
      ]
    )
  }

  @Test("importing OPML with URLNotFound errors")
  func importOPMLWithURLNotFoundErrors() async throws {
    // Setup: Create OPML with 3 feeds, 1 valid and 2 with 404 errors
    let validFeedURL = URL(string: "https://api.substack.com/feed/podcast/10845.rss")!
    let notFoundFeed1URL = URL(string: "https://feeds.invalid.com/notfound1")!
    let notFoundFeed2URL = URL(string: "https://feeds.invalid.com/notfound2")!

    let opmlURL = createTestOPMLURL()
    await setupOPMLResponse(
      to: opmlURL,
      feeds: [
        (title: "Lenny's Podcast", url: validFeedURL.absoluteString),
        (title: "Not Found Feed 1", url: notFoundFeed1URL.absoluteString),
        (title: "Not Found Feed 2", url: notFoundFeed2URL.absoluteString),
      ]
    )

    await setupValidFeedResponse(to: validFeedURL, assetName: "lenny")
    await setupNotFoundFeedResponse(to: notFoundFeed1URL)
    await setupNotFoundFeedResponse(to: notFoundFeed2URL)

    // Verify initial state
    #expect(try await repo.allPodcasts(AppDB.NoOp).isEmpty)

    // Execute and wait for completion
    try await importOPML(from: opmlURL)
    try await waitForAllComplete()

    // Verify final state: 1 finished, 2 failed
    try await verifyOPMLFileState(
      totalCount: 3,
      finished: 1,
      failed: 2
    )

    // Verify only valid podcast was saved to repo
    try await verifyPodcastsInRepo(
      expectedCount: 1,
      feedURLs: [validFeedURL.absoluteString]
    )
  }

  @Test("importing OPML verifies progress tracking transitions")
  func importOPMLVerifiesProgressTracking() async throws {
    // Setup: Create OPML with 2 feeds
    let feed1URL = URL(string: "https://api.substack.com/feed/podcast/10845.rss")!
    let feed2URL = URL(string: "https://feeds.simplecast.com/l2i9YnTd")!

    let opmlURL = createTestOPMLURL()
    await setupOPMLResponse(
      to: opmlURL,
      feeds: [
        (title: "Lenny's Podcast", url: feed1URL.absoluteString),
        (title: "Hard Fork", url: feed2URL.absoluteString),
      ]
    )

    // Setup feed responses with controlled timing
    let feed1Data = PreviewBundle.loadAsset(named: "lenny", in: .FeedRSS)
    let feed1Semaphore = await feedSession.waitRespond(to: feed1URL, data: feed1Data)

    let feed2Data = PreviewBundle.loadAsset(named: "hardfork_short", in: .FeedRSS)
    let feed2Semaphore = await feedSession.waitRespond(to: feed2URL, data: feed2Data)

    // Execute
    Task { await opmlViewModel.importOPMLFromURL(url: opmlURL) }

    // Wait for OPMLFile to be created and verify initial state
    let opmlFile = try await waitForOPMLFile()
    try await waitForDownloadingCount(2)

    // Verify no feeds are finished or failed yet
    try await verifyOPMLFileState(
      downloading: 2,
      finished: 0,
      failed: 0
    )

    // Release first feed and verify transition to finished
    feed1Semaphore.signal()
    try await waitForFinishedCount(1)

    // At this point we should have: 1 finished, potentially 1 waiting or downloading
    #expect(opmlFile.finished.count == 1)
    #expect(opmlFile.waiting.count + opmlFile.downloading.count == 1)

    // Release second feed and wait for completion
    feed2Semaphore.signal()
    try await waitForAllComplete()

    // Verify final state
    try await verifyOPMLFileState(
      waiting: 0,
      downloading: 0,
      finished: 2,
      failed: 0
    )

    // Verify podcasts were saved
    try await verifyPodcastsInRepo(expectedCount: 2)
  }

  @Test("importing OPML with already subscribed podcast")
  func importOPMLWithAlreadySubscribedPodcast() async throws {
    // Setup: Pre-populate database with one subscribed podcast
    let existingFeedURL = URL(string: "https://api.substack.com/feed/podcast/10845.rss")!
    try await insertPodcastSeries(
      feedURL: existingFeedURL,
      assetName: "lenny",
      subscribed: true
    )

    // Create OPML with the existing podcast and a new one
    let newFeedURL = URL(string: "https://feeds.simplecast.com/l2i9YnTd")!

    let opmlURL = createTestOPMLURL()
    await setupOPMLResponse(
      to: opmlURL,
      feeds: [
        (title: "Lenny's Podcast", url: existingFeedURL.absoluteString),
        (title: "Hard Fork", url: newFeedURL.absoluteString),
      ]
    )

    // Setup feed response for new podcast only
    await setupValidFeedResponse(to: newFeedURL, assetName: "hardfork_short")

    // Verify initial state: 1 podcast already exists
    #expect(try await repo.allPodcasts(AppDB.NoOp).count == 1)

    // Execute and wait for completion
    try await importOPML(from: opmlURL)
    try await waitForAllComplete()

    // Verify final state: both podcasts are finished
    try await verifyOPMLFileState(
      finished: 2,
      failed: 0
    )

    // Verify podcasts in repo: should still be 2 total (1 existing + 1 new)
    try await verifyPodcastsInRepo(expectedCount: 2)
  }

  @Test("importing OPML with unsubscribed existing podcast")
  func importOPMLWithUnsubscribedExistingPodcast() async throws {
    // Setup: Pre-populate database with an unsubscribed podcast
    let existingFeedURL = URL(string: "https://api.substack.com/feed/podcast/10845.rss")!
    let existingSeries = try await insertPodcastSeries(
      feedURL: existingFeedURL,
      assetName: "lenny",
      subscribed: false
    )

    // Verify it's not subscribed
    let unsubscribedPodcast = try await repo.podcastSeries(existingSeries.id)!.podcast
    #expect(!unsubscribedPodcast.subscribed)

    // Create OPML with the existing podcast
    let opmlURL = createTestOPMLURL()
    await setupOPMLResponse(
      to: opmlURL,
      feeds: [(title: "Lenny's Podcast", url: existingFeedURL.absoluteString)]
    )

    // Execute and wait for completion
    try await importOPML(from: opmlURL)
    try await waitForAllComplete()

    // Verify the podcast is now marked as subscribed
    let subscribedPodcast = try await repo.podcastSeries(existingSeries.id)!.podcast
    #expect(subscribedPodcast.subscribed)

    // Verify it's marked as finished in OPML
    try await verifyOPMLFileState(
      finished: 1,
      failed: 0
    )
  }

  // MARK: - Helpers

  func createTestOPML(
    title: String = "Test OPML Subscriptions",
    feeds: [(title: String, url: String)]
  ) -> Data {
    var outlines = ""
    for feed in feeds {
      outlines +=
        """
          <outline type="rss" text="\(feed.title)" title="\(feed.title)" xmlUrl="\(feed.url)"/>

        """
    }

    let opmlString = """
      <?xml version="1.0"?>
      <opml version="1.0">
      <head><title>\(title)</title></head>
      <body>
      \(outlines)</body>
      </opml>
      """

    return opmlString.data(using: .utf8)!
  }

  func createTestOPMLURL() -> URL {
    URL(string: "file:///test.opml")!
  }

  // MARK: - Feed Response Setup Helpers

  func setupOPMLResponse(
    to opmlURL: URL,
    feeds: [(title: String, url: String)],
    title: String = "Test OPML Subscriptions"
  ) async {
    let opmlData = createTestOPML(title: title, feeds: feeds)
    await opmlSession.respond(to: opmlURL, data: opmlData)
  }

  func setupValidFeedResponse(to feedURL: URL, assetName: String) async {
    let feedData = PreviewBundle.loadAsset(named: assetName, in: .FeedRSS)
    await feedSession.respond(to: feedURL, data: feedData)
  }

  func setupMalformedFeedResponse(to feedURL: URL) async {
    let malformedData = PreviewBundle.loadAsset(named: "game_informer_invalid", in: .FeedRSS)
    await feedSession.respond(to: feedURL, data: malformedData)
  }

  func setupNotFoundFeedResponse(to feedURL: URL) async {
    await feedSession.respond(
      to: feedURL,
      error: DownloadError.notOKResponseCode(code: 404, url: feedURL)
    )
  }

  func setupFeedError(to feedURL: URL, error: Error) async {
    await feedSession.respond(to: feedURL, error: error)
  }

  // MARK: - Import Helpers

  @discardableResult
  func importOPML(from url: URL) async throws -> OPMLFile {
    await opmlViewModel.importOPMLFromURL(url: url)
    return try await waitForOPMLFile()
  }

  // MARK: - Wait Helpers

  @discardableResult
  func waitForOPMLFile() async throws -> OPMLFile {
    try await Wait.forValue {
      await self.opmlViewModel.opmlFile
    }
  }

  func waitForInProgressCount(_ expectedCount: Int) async throws {
    let opmlFile = try await waitForOPMLFile()
    try await Wait.until(
      { @MainActor in opmlFile.inProgressCount == expectedCount },
      { @MainActor in
        "Expected inProgressCount to be \(expectedCount), but got \(opmlFile.inProgressCount)"
      }
    )
  }

  func waitForAllComplete() async throws {
    try await waitForInProgressCount(0)
  }

  func waitForWaitingCount(_ expectedCount: Int) async throws {
    let opmlFile = try await waitForOPMLFile()
    try await Wait.until(
      { @MainActor in opmlFile.waiting.count == expectedCount },
      { @MainActor in
        "Expected waiting count to be \(expectedCount), but got \(opmlFile.waiting.count)"
      }
    )
  }

  func waitForDownloadingCount(_ expectedCount: Int) async throws {
    let opmlFile = try await waitForOPMLFile()
    try await Wait.until(
      { @MainActor in opmlFile.downloading.count == expectedCount },
      { @MainActor in
        "Expected downloading count to be \(expectedCount), but got \(opmlFile.downloading.count)"
      }
    )
  }

  func waitForFinishedCount(_ expectedCount: Int) async throws {
    let opmlFile = try await waitForOPMLFile()
    try await Wait.until(
      { @MainActor in opmlFile.finished.count == expectedCount },
      { @MainActor in
        "Expected finished count to be \(expectedCount), but got \(opmlFile.finished.count)"
      }
    )
  }

  func waitForFailedCount(_ expectedCount: Int) async throws {
    let opmlFile = try await waitForOPMLFile()
    try await Wait.until(
      { @MainActor in opmlFile.failed.count == expectedCount },
      { @MainActor in
        "Expected failed count to be \(expectedCount), but got \(opmlFile.failed.count)"
      }
    )
  }

  // MARK: - Verification Helpers

  func verifyOPMLFileState(
    title: String? = nil,
    totalCount: Int? = nil,
    waiting: Int? = nil,
    downloading: Int? = nil,
    finished: Int? = nil,
    failed: Int? = nil
  ) async throws {
    let opmlFile = try await waitForOPMLFile()

    if let title = title {
      #expect(opmlFile.title == title)
    }

    if let totalCount = totalCount {
      #expect(opmlFile.totalCount == totalCount)
    }

    if let waiting = waiting {
      #expect(opmlFile.waiting.count == waiting)
    }

    if let downloading = downloading {
      #expect(opmlFile.downloading.count == downloading)
    }

    if let finished = finished {
      #expect(opmlFile.finished.count == finished)
    }

    if let failed = failed {
      #expect(opmlFile.failed.count == failed)
    }
  }

  func verifyPodcastsInRepo(
    expectedCount: Int,
    allSubscribed: Bool = true,
    feedURLs: Set<String>? = nil
  ) async throws {
    let savedPodcasts = try await repo.allPodcasts(AppDB.NoOp)
    #expect(savedPodcasts.count == expectedCount)

    if allSubscribed {
      #expect(savedPodcasts.allSatisfy { $0.subscribed })
    }

    if let feedURLs = feedURLs {
      let actualURLs = Set(savedPodcasts.map { $0.feedURL.absoluteString })
      #expect(actualURLs == feedURLs)
    }
  }

  // MARK: - Database Setup Helpers

  @discardableResult
  func insertPodcastSeries(
    feedURL: URL,
    assetName: String,
    subscribed: Bool = false
  ) async throws -> PodcastSeries {
    let feedData = PreviewBundle.loadAsset(named: assetName, in: .FeedRSS)
    let podcastFeed = try await PodcastFeed.parse(feedData, from: FeedURL(feedURL))

    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try podcastFeed.toUnsavedPodcast(),
        unsavedEpisodes: podcastFeed.toUnsavedEpisodes()
      )
    )

    if subscribed {
      try await repo.markSubscribed(series.id)
    }

    return series
  }

}
