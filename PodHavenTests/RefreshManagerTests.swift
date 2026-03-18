// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Semaphore
import Testing

@testable import PodHaven

@Suite("of RefreshManager tests", .container)
actor RefreshManagerTests {
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.podcastFeedSession) private var podcastFeedSession
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.refreshManager) private var refreshManager
  @DynamicInjected(\.userNotificationCenter) private var userNotificationCenter

  var session: FakeDataFetchable { podcastFeedSession as! FakeDataFetchable }
  var fakeRepo: FakeRepo { repo as! FakeRepo }
  var fakeUserNotificationCenter: FakeUserNotificationCenter {
    userNotificationCenter as! FakeUserNotificationCenter
  }

  @Test("that refreshSeries works")
  func testRefreshSeriesWorks() async throws {
    let data = PreviewBundle.loadAsset(named: "hardfork_short", in: .FeedRSS)
    let fakeURL = FeedURL(URL(string: "https://example.com/feed.rss")!)
    let podcastFeed = try await PodcastFeed.parse(data, from: fakeURL)
    let unsavedPodcast = try podcastFeed.toUnsavedPodcast()
    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: podcastFeed.toUnsavedEpisodes()
      )
    )

    #expect(podcastSeries.podcast.title == "Hard Fork")
    #expect(podcastSeries.episodes.count == 2)
    #expect(
      podcastSeries.episodes.map({ $0.title }) == [
        "Our 2025 Tech Predictions and Resolutions + We Answer Your Questions",
        "The Wirecutter Show: Kitchen Gear That Lasts a Lifetime (or Extremely Close)",
      ]
    )

    let updatedData = PreviewBundle.loadAsset(
      named: "hardfork_short_updated",
      in: .FeedRSS
    )
    await session.respond(to: podcastSeries.podcast.feedURL.rawValue, data: updatedData)
    try await refreshManager.refreshSeries(podcastSeries: podcastSeries)

    let updatedSeries = try await repo.podcastSeries(podcastSeries.podcast.id)!
    #expect(updatedSeries.podcast.lastUpdate.approximatelyEquals(Date()))
    #expect(
      updatedSeries.podcast.feedURL
        == FeedURL(URL(string: "https://feeds.simplecast.com/l2i9YnTdNEW")!)
    )
    #expect(updatedSeries.podcast.title == "Hard Fork version 2")
    #expect(updatedSeries.episodes.count == 3)
    #expect(
      updatedSeries.episodes.map({ $0.title }) == [
        "Our 2026 Tech Predictions and Resolutions + We Answer Your Questions",
        "Gear That Lasts a Lifetime Updated",
        "Is Amazon's Drone Delivery Finally Ready for Prime Time?",
      ]
    )
  }

  @Test("that refreshSeries still updates lastUpdate even when everything else is the same")
  func testRefreshSeriesWorksAlwaysUpdatesLastUpdate() async throws {
    let data = PreviewBundle.loadAsset(named: "hardfork_short", in: .FeedRSS)
    let fakeURL = FeedURL(URL(string: "https://example.com/feed.rss")!)
    let podcastFeed = try await PodcastFeed.parse(data, from: fakeURL)
    let unsavedPodcast = try podcastFeed.toUnsavedPodcast()
    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: podcastFeed.toUnsavedEpisodes()
      )
    )

    let updatedData = PreviewBundle.loadAsset(named: "hardfork_short", in: .FeedRSS)
    await session.respond(to: podcastSeries.podcast.feedURL.rawValue, data: updatedData)
    try await refreshManager.refreshSeries(podcastSeries: podcastSeries)

    let updatedSeries = try await repo.podcastSeries(podcastSeries.podcast.id)!
    #expect(updatedSeries.podcast.lastUpdate.approximatelyEquals(Date()))
  }

  @Test("that selective updates only update changed content")
  func testSelectiveUpdates() async throws {
    let data = PreviewBundle.loadAsset(named: "hardfork_short", in: .FeedRSS)
    let fakeURL = FeedURL(URL(string: "https://example.com/feed.rss")!)
    let podcastFeed = try await PodcastFeed.parse(data, from: fakeURL)
    let unsavedPodcast = try podcastFeed.toUnsavedPodcast()
    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: podcastFeed.toUnsavedEpisodes()
      )
    )

    fakeRepo.clearAllCalls()

    let updatedData = PreviewBundle.loadAsset(
      named: "hardfork_short_updated",
      in: .FeedRSS
    )
    await session.respond(to: podcastSeries.podcast.feedURL.rawValue, data: updatedData)
    try await refreshManager.refreshSeries(podcastSeries: podcastSeries)

    let call = try fakeRepo.expectCall(
      methodName: "updateSeriesFromFeed",
      parameters: (
        podcastSeries: PodcastSeries,
        podcast: Podcast?,
        unsavedEpisodes: [UnsavedEpisode],
        existingEpisodes: [Episode]
      )
      .self
    )
    #expect(call.parameters.podcastSeries == podcastSeries)
    #expect(call.parameters.podcast != nil)
    #expect(call.parameters.unsavedEpisodes.count == 1)
    #expect(call.parameters.existingEpisodes.count == 2)
  }

  @Test("that new episodes with duplicate MediaURLs are deduped")
  func testDedupingNewMediaURLs() async throws {
    let data = PreviewBundle.loadAsset(named: "hardfork_short", in: .FeedRSS)
    let fakeURL = FeedURL(URL(string: "https://example.com/feed.rss")!)
    let podcastFeed = try await PodcastFeed.parse(data, from: fakeURL)
    let unsavedPodcast = try podcastFeed.toUnsavedPodcast()
    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: podcastFeed.toUnsavedEpisodes()
      )
    )

    let updatedData = PreviewBundle.loadAsset(
      named: "hardfork_short_updated_dupe_mediaURL",
      in: .FeedRSS
    )
    await session.respond(to: podcastSeries.podcast.feedURL.rawValue, data: updatedData)

    // One test is that this doesn't throw a UNIQUE constraint error on MediaURLs
    try await refreshManager.refreshSeries(podcastSeries: podcastSeries)

    let updatedSeries = try await repo.podcastSeries(podcastSeries.podcast.id)!
    #expect(
      Set(updatedSeries.episodes.map({ $0.mediaURL }))
        .contains(MediaURL(URL(string: "https://dts.podtrac.com/redirect_dupe.mp3/")!))
    )
  }

  @Test("that new episodes with duplicate GUIDs are deduped")
  func testDedupingNewGUIDs() async throws {
    let data = PreviewBundle.loadAsset(named: "hardfork_short", in: .FeedRSS)
    let fakeURL = FeedURL(URL(string: "https://example.com/feed.rss")!)
    let podcastFeed = try await PodcastFeed.parse(data, from: fakeURL)
    let unsavedPodcast = try podcastFeed.toUnsavedPodcast()
    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: podcastFeed.toUnsavedEpisodes()
      )
    )

    let updatedData = PreviewBundle.loadAsset(
      named: "hardfork_short_updated_dupe_guid",
      in: .FeedRSS
    )
    await session.respond(to: podcastSeries.podcast.feedURL.rawValue, data: updatedData)

    // One test is that this doesn't throw a UNIQUE constraint error on GUIDs
    try await refreshManager.refreshSeries(podcastSeries: podcastSeries)

    let updatedSeries = try await repo.podcastSeries(podcastSeries.podcast.id)!
    #expect(Set(updatedSeries.episodes.map({ $0.guid })).contains(GUID("dupe_guid")))
  }

  @Test("that no repo calls occur when content is unchanged")
  func testNoRepoCallsWhenContentUnchanged() async throws {
    let data = PreviewBundle.loadAsset(named: "hardfork_short", in: .FeedRSS)
    let fakeURL = FeedURL(URL(string: "https://example.com/feed.rss")!)
    let podcastFeed = try await PodcastFeed.parse(data, from: fakeURL)
    let unsavedPodcast = try podcastFeed.toUnsavedPodcast()
    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: podcastFeed.toUnsavedEpisodes()
      )
    )

    fakeRepo.clearAllCalls()

    await session.respond(to: podcastSeries.podcast.feedURL.rawValue, data: data)
    try await refreshManager.refreshSeries(podcastSeries: podcastSeries)

    try fakeRepo.expectNoCall(methodName: "updateSeriesFromFeed")
  }

  // This is invalid behavior by a feed but sadly dumb dumbs still do it.
  @Test("that a feed can update when the guid changes with the same media")
  func testFeedUpdatesWhenGuidChangesButMediaRemainsSame() async throws {
    let data = PreviewBundle.loadAsset(named: "thisamericanlife", in: .FeedRSS)
    let fakeURL = FeedURL(URL(string: "https://example.com/feed.rss")!)
    let podcastFeed = try await PodcastFeed.parse(data, from: fakeURL)
    let unsavedPodcast = try podcastFeed.toUnsavedPodcast()
    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: podcastFeed.toUnsavedEpisodes()
      )
    )

    let originalEpisode = podcastSeries.episodes.first(where: {
      $0.guid == GUID("37163 at https://www.thisamericanlife.org")
    })!
    #expect(originalEpisode.title == "510: Fiasco! (2013)")

    let expectedDuration = CMTime.seconds(2_468)
    let expectedCurrentTime = CMTime.seconds(321)
    let episodeID = originalEpisode.id
    try await repo.markFinished(episodeID)
    let completionSeedEpisode = try await repo.episode(episodeID)!
    let expectedFinishDate = completionSeedEpisode.finishDate!
    try await repo.updateDuration(episodeID, duration: expectedDuration)
    try await repo.updateCurrentTime(episodeID, currentTime: expectedCurrentTime)

    let updatedData = PreviewBundle.loadAsset(
      named: "thisamericanlife_updated",
      in: .FeedRSS
    )
    await session.respond(to: podcastSeries.podcast.feedURL.rawValue, data: updatedData)
    try await refreshManager.refreshSeries(podcastSeries: podcastSeries)

    let updatedSeries = try await repo.podcastSeries(podcastSeries.podcast.id)!
    let updatedEpisodeByID = try await repo.episode(episodeID)!
    #expect(updatedEpisodeByID.currentTime.seconds == expectedCurrentTime.seconds)
    #expect(updatedEpisodeByID.duration.seconds == expectedDuration.seconds)
    #expect(updatedEpisodeByID.finishDate?.approximatelyEquals(expectedFinishDate) == true)

    // Old guid that got changed
    #expect(
      updatedSeries.episodes.first(where: {
        $0.guid == GUID("37163 at https://www.thisamericanlife.org")
      }) == nil
    )

    // New guid
    let updatedEpisode = updatedSeries.episodes.first(where: {
      $0.guid == GUID("45921 at https://www.thisamericanlife.org")
    })!
    #expect(
      updatedEpisode.mediaURL
        == MediaURL(
          URL(
            string:
              "https://pfx.vpixl.com/6qj4J/dts.podtrac.com/redirect.mp3/chrt.fm/track/138C95/pdst.fm/e/prefix.up.audio/s/traffic.megaphone.fm/NPR4143637574.mp3"
          )!
        )
    )
    #expect(updatedEpisode.title == "511: Fiasco! (2013)")
  }

  @Test("refreshManager ignores request for already being fetched URL")
  func refreshManagerIgnoresRequestForAlreadyBeingFetchedURL() async throws {
    let data = PreviewBundle.loadAsset(named: "hardfork_short", in: .FeedRSS)
    let fakeURL = FeedURL(URL(string: "https://example.com/feed.rss")!)
    let podcastFeed = try await PodcastFeed.parse(data, from: fakeURL)
    let unsavedPodcast = try podcastFeed.toUnsavedPodcast()
    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: podcastFeed.toUnsavedEpisodes()
      )
    )

    let updatedData = PreviewBundle.loadAsset(
      named: "hardfork_short_updated",
      in: .FeedRSS
    )

    let (startedSemaphore, finishSemaphore) = await session.releaseWaitRespond(
      to: podcastSeries.podcast.feedURL.rawValue,
      data: updatedData
    )

    Task { try await refreshManager.refreshSeries(podcastSeries: podcastSeries) }
    try await startedSemaphore.waitUnlessCancelled()

    // The test is that this second call doesn't hang because it early exits.
    try await refreshManager.refreshSeries(podcastSeries: podcastSeries)
    finishSemaphore.signal()
  }

  @Test("refreshSeries queues new episodes on top when queueAllEpisodes is .onTop")
  func testRefreshSeriesQueuesNewEpisodesOnTop() async throws {
    let data = PreviewBundle.loadAsset(named: "hardfork_short", in: .FeedRSS)
    let fakeURL = FeedURL(URL(string: "https://example.com/feed.rss")!)
    let podcastFeed = try await PodcastFeed.parse(data, from: fakeURL)

    // Create podcast with queueAllEpisodes set to .onTop
    let basePodcast = try podcastFeed.toUnsavedPodcast()
    let unsavedPodcast = try UnsavedPodcast(
      feedURL: basePodcast.feedURL,
      title: basePodcast.title,
      image: basePodcast.image,
      description: basePodcast.description,
      link: basePodcast.link,
      queueAllEpisodes: .onTop
    )
    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: podcastFeed.toUnsavedEpisodes()
      )
    )

    // Add existing episodes to queue
    let existingEpisodeIDs = podcastSeries.episodes.map(\.id)
    try await queue.append(existingEpisodeIDs)

    // Verify initial queue state
    var queuedIDs = try await PlayHelpers.queuedEpisodeIDs
    #expect(queuedIDs == existingEpisodeIDs)

    // Set up updated feed with a new episode
    let updatedData = PreviewBundle.loadAsset(
      named: "hardfork_short_updated",
      in: .FeedRSS
    )
    await session.respond(to: podcastSeries.podcast.feedURL.rawValue, data: updatedData)
    try await refreshManager.refreshSeries(podcastSeries: podcastSeries)

    // Wait for new episodes to be queued on top
    try await Wait.until(
      { try await PlayHelpers.queuedEpisodeIDs.count == 3 },
      { "Expected 3 queued episodes, got \(try await PlayHelpers.queuedEpisodeIDs.count)" }
    )

    // Get the updated series to find the new episode
    let updatedSeries = try await repo.podcastSeries(podcastSeries.id)!
    let newEpisode = updatedSeries.episodes.first { episode in
      !existingEpisodeIDs.contains(episode.id)
    }!

    // Verify new episode is at the top of the queue
    queuedIDs = try await PlayHelpers.queuedEpisodeIDs
    #expect(queuedIDs.first == newEpisode.id)
    #expect(queuedIDs.count == 3)
  }

  @Test("refreshSeries queues new episodes on bottom when queueAllEpisodes is .onBottom")
  func testRefreshSeriesQueuesNewEpisodesOnBottom() async throws {
    let data = PreviewBundle.loadAsset(named: "hardfork_short", in: .FeedRSS)
    let fakeURL = FeedURL(URL(string: "https://example.com/feed.rss")!)
    let podcastFeed = try await PodcastFeed.parse(data, from: fakeURL)

    // Create podcast with queueAllEpisodes set to .onBottom
    let basePodcast = try podcastFeed.toUnsavedPodcast()
    let unsavedPodcast = try UnsavedPodcast(
      feedURL: basePodcast.feedURL,
      title: basePodcast.title,
      image: basePodcast.image,
      description: basePodcast.description,
      link: basePodcast.link,
      queueAllEpisodes: .onBottom
    )
    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: podcastFeed.toUnsavedEpisodes()
      )
    )

    // Add existing episodes to queue
    let existingEpisodeIDs = podcastSeries.episodes.map(\.id)
    try await queue.append(existingEpisodeIDs)

    // Verify initial queue state
    var queuedIDs = try await PlayHelpers.queuedEpisodeIDs
    #expect(queuedIDs == existingEpisodeIDs)

    // Set up updated feed with a new episode
    let updatedData = PreviewBundle.loadAsset(
      named: "hardfork_short_updated",
      in: .FeedRSS
    )
    await session.respond(to: podcastSeries.podcast.feedURL.rawValue, data: updatedData)
    try await refreshManager.refreshSeries(podcastSeries: podcastSeries)

    // Wait for new episodes to be queued on bottom
    try await Wait.until(
      { try await PlayHelpers.queuedEpisodeIDs.count == 3 },
      { "Expected 3 queued episodes, got \(try await PlayHelpers.queuedEpisodeIDs.count)" }
    )

    // Get the updated series to find the new episode
    let updatedSeries = try await repo.podcastSeries(podcastSeries.id)!
    let newEpisode = updatedSeries.episodes.first { episode in
      !existingEpisodeIDs.contains(episode.id)
    }!

    // Verify new episode is at the bottom of the queue
    queuedIDs = try await PlayHelpers.queuedEpisodeIDs
    #expect(queuedIDs.last == newEpisode.id)
    #expect(queuedIDs.count == 3)
  }

  @Test("refreshSeries does not queue new episodes when queueAllEpisodes is .never")
  func testRefreshSeriesDoesNotQueueNewEpisodesWhenNever() async throws {
    let data = PreviewBundle.loadAsset(named: "hardfork_short", in: .FeedRSS)
    let fakeURL = FeedURL(URL(string: "https://example.com/feed.rss")!)
    let podcastFeed = try await PodcastFeed.parse(data, from: fakeURL)

    // Create podcast with queueAllEpisodes set to .never (default)
    let basePodcast = try podcastFeed.toUnsavedPodcast()
    let unsavedPodcast = try UnsavedPodcast(
      feedURL: basePodcast.feedURL,
      title: basePodcast.title,
      image: basePodcast.image,
      description: basePodcast.description,
      link: basePodcast.link,
      queueAllEpisodes: .never
    )
    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: podcastFeed.toUnsavedEpisodes()
      )
    )

    // Add existing episodes to queue
    let existingEpisodeIDs = podcastSeries.episodes.map(\.id)
    try await queue.append(existingEpisodeIDs)

    // Verify initial queue state
    var queuedIDs = try await PlayHelpers.queuedEpisodeIDs
    #expect(queuedIDs == existingEpisodeIDs)

    // Set up updated feed with a new episode
    let updatedData = PreviewBundle.loadAsset(
      named: "hardfork_short_updated",
      in: .FeedRSS
    )
    await session.respond(to: podcastSeries.podcast.feedURL.rawValue, data: updatedData)
    try await refreshManager.refreshSeries(podcastSeries: podcastSeries)

    // Verify series was updated with new episode
    let updatedSeries = try await repo.podcastSeries(podcastSeries.id)!
    #expect(updatedSeries.episodes.count == 3)

    // Verify queue still only contains the original episodes
    queuedIDs = try await PlayHelpers.queuedEpisodeIDs
    #expect(queuedIDs == existingEpisodeIDs)
    #expect(queuedIDs.count == 2)
  }

  @Test("refreshSeries schedules new episode notifications when notifyNewEpisodes is true")
  func testRefreshSeriesSchedulesNewEpisodeNotifications() async throws {
    let data = PreviewBundle.loadAsset(named: "hardfork_short", in: .FeedRSS)
    let fakeURL = FeedURL(URL(string: "https://example.com/feed.rss")!)
    let podcastFeed = try await PodcastFeed.parse(data, from: fakeURL)

    // Create podcast with notifyNewEpisodes set to true
    let basePodcast = try podcastFeed.toUnsavedPodcast()
    let unsavedPodcast = try UnsavedPodcast(
      feedURL: basePodcast.feedURL,
      title: basePodcast.title,
      image: basePodcast.image,
      description: basePodcast.description,
      link: basePodcast.link,
      notifyNewEpisodes: true  // Crucial for this test
    )
    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: podcastFeed.toUnsavedEpisodes()
      )
    )

    fakeUserNotificationCenter.clearAllCalls()

    // Set up updated feed with a new episode
    let updatedData = PreviewBundle.loadAsset(
      named: "hardfork_short_updated",
      in: .FeedRSS
    )
    await session.respond(to: podcastSeries.podcast.feedURL.rawValue, data: updatedData)
    try await refreshManager.refreshSeries(podcastSeries: podcastSeries)

    // Get the updated series to find the new episode
    let updatedSeries = try await repo.podcastSeries(podcastSeries.id)!
    let existingEpisodeIDs = Set(podcastSeries.episodes.map(\.id))
    let newEpisode = updatedSeries.episodes.first { episode in
      !existingEpisodeIDs.contains(episode.id)
    }!

    // Verify that a notification request was added
    #expect(fakeUserNotificationCenter.addedRequests.count == 1)
    let request = fakeUserNotificationCenter.addedRequests.first!
    #expect(request.title == podcastSeries.podcast.title)
    #expect(request.body == newEpisode.title)
  }

  @Test("refreshSeries caches new episodes when cacheAllEpisodes is .cache")
  func testRefreshSeriesCachesNewEpisodesWhenEnabled() async throws {
    let data = PreviewBundle.loadAsset(named: "hardfork_short", in: .FeedRSS)
    let fakeURL = FeedURL(URL(string: "https://example.com/feed.rss")!)
    let podcastFeed = try await PodcastFeed.parse(data, from: fakeURL)

    // Create podcast with cacheAllEpisodes set to .cache
    let basePodcast = try podcastFeed.toUnsavedPodcast()
    let unsavedPodcast = try UnsavedPodcast(
      feedURL: basePodcast.feedURL,
      title: basePodcast.title,
      image: basePodcast.image,
      description: basePodcast.description,
      link: basePodcast.link,
      cacheAllEpisodes: .cache
    )
    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: podcastFeed.toUnsavedEpisodes()
      )
    )

    // Verify initial state - no episodes are cached
    #expect(podcastSeries.episodes.allSatisfy { $0.cacheStatus != .cached })

    // Set up updated feed with a new episode
    let updatedData = PreviewBundle.loadAsset(
      named: "hardfork_short_updated",
      in: .FeedRSS
    )
    await session.respond(to: podcastSeries.podcast.feedURL.rawValue, data: updatedData)
    try await refreshManager.refreshSeries(podcastSeries: podcastSeries)

    // Get the updated series to find the new episode
    let updatedSeries = try await repo.podcastSeries(podcastSeries.id)!
    let existingEpisodeIDs = Set(podcastSeries.episodes.map(\.id))
    let newEpisode = updatedSeries.episodes.first { episode in
      !existingEpisodeIDs.contains(episode.id)
    }!

    // Wait for new episode to start being cached
    _ = try await CacheHelpers.waitForDownloadTaskID(newEpisode.id)

    // Verify the new episode has a download task (indicating it's being cached)
    let episodeAfterRefresh = try await repo.episode(newEpisode.id)!
    #expect(episodeAfterRefresh.downloadTaskID != nil)
    // saveInCache should remain false for .cache mode
    #expect(episodeAfterRefresh.saveInCache == false)
  }

  @Test("refreshSeries does not cache new episodes when cacheAllEpisodes is .never")
  func testRefreshSeriesDoesNotCacheNewEpisodesWhenDisabled() async throws {
    let data = PreviewBundle.loadAsset(named: "hardfork_short", in: .FeedRSS)
    let fakeURL = FeedURL(URL(string: "https://example.com/feed.rss")!)
    let podcastFeed = try await PodcastFeed.parse(data, from: fakeURL)

    // Create podcast with cacheAllEpisodes set to .never (default)
    let basePodcast = try podcastFeed.toUnsavedPodcast()
    let unsavedPodcast = try UnsavedPodcast(
      feedURL: basePodcast.feedURL,
      title: basePodcast.title,
      image: basePodcast.image,
      description: basePodcast.description,
      link: basePodcast.link,
      cacheAllEpisodes: .never
    )
    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: podcastFeed.toUnsavedEpisodes()
      )
    )

    // Verify initial state - no episodes are cached
    #expect(podcastSeries.episodes.allSatisfy { $0.cacheStatus != .cached })

    // Set up updated feed with a new episode
    let updatedData = PreviewBundle.loadAsset(
      named: "hardfork_short_updated",
      in: .FeedRSS
    )
    await session.respond(to: podcastSeries.podcast.feedURL.rawValue, data: updatedData)
    try await refreshManager.refreshSeries(podcastSeries: podcastSeries)

    // Verify series was updated with new episode
    let updatedSeries = try await repo.podcastSeries(podcastSeries.id)!
    #expect(updatedSeries.episodes.count == 3)

    // Get the new episode
    let existingEpisodeIDs = Set(podcastSeries.episodes.map(\.id))
    let newEpisode = updatedSeries.episodes.first { episode in
      !existingEpisodeIDs.contains(episode.id)
    }!

    // Verify the new episode was not cached
    let episodeAfterRefresh = try await repo.episode(newEpisode.id)!
    #expect(episodeAfterRefresh.cacheStatus != .cached)
    #expect(episodeAfterRefresh.downloadTaskID == nil)
  }

  @Test("refreshSeries caches and saves new episodes when cacheAllEpisodes is .save")
  func testRefreshSeriesCachesAndSavesNewEpisodesWhenSaveEnabled() async throws {
    let data = PreviewBundle.loadAsset(named: "hardfork_short", in: .FeedRSS)
    let fakeURL = FeedURL(URL(string: "https://example.com/feed.rss")!)
    let podcastFeed = try await PodcastFeed.parse(data, from: fakeURL)

    // Create podcast with cacheAllEpisodes set to .save
    let basePodcast = try podcastFeed.toUnsavedPodcast()
    let unsavedPodcast = try UnsavedPodcast(
      feedURL: basePodcast.feedURL,
      title: basePodcast.title,
      image: basePodcast.image,
      description: basePodcast.description,
      link: basePodcast.link,
      cacheAllEpisodes: .save
    )
    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: podcastFeed.toUnsavedEpisodes()
      )
    )

    // Verify initial state - no episodes are cached and saveInCache is false
    #expect(podcastSeries.episodes.allSatisfy { $0.cacheStatus != .cached })
    #expect(podcastSeries.episodes.allSatisfy { $0.saveInCache == false })

    // Set up updated feed with a new episode
    let updatedData = PreviewBundle.loadAsset(
      named: "hardfork_short_updated",
      in: .FeedRSS
    )
    await session.respond(to: podcastSeries.podcast.feedURL.rawValue, data: updatedData)
    try await refreshManager.refreshSeries(podcastSeries: podcastSeries)

    // Get the updated series to find the new episode
    let updatedSeries = try await repo.podcastSeries(podcastSeries.id)!
    let existingEpisodeIDs = Set(podcastSeries.episodes.map(\.id))
    let newEpisode = updatedSeries.episodes.first { episode in
      !existingEpisodeIDs.contains(episode.id)
    }!

    // Wait for new episode to start being cached
    _ = try await CacheHelpers.waitForDownloadTaskID(newEpisode.id)

    // Verify the new episode has a download task (indicating it's being cached)
    let episodeAfterRefresh = try await repo.episode(newEpisode.id)!
    #expect(episodeAfterRefresh.downloadTaskID != nil)
    // saveInCache should be set to true for .save mode
    #expect(episodeAfterRefresh.saveInCache == true)

    // Verify existing episodes were NOT modified (saveInCache should still be false)
    for existingEpisodeID in existingEpisodeIDs {
      let existingEpisode = try await repo.episode(existingEpisodeID)!
      #expect(existingEpisode.saveInCache == false)
    }
  }
}
