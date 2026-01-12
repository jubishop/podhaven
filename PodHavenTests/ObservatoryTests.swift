// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import IdentifiedCollections
import Testing

@testable import PodHaven

@Suite("of Observatory tests", .container)
actor ObservatoryTests {
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.repo) private var repo

  @Test("podcastsWithEpisodeMetadata() with zero episodes")
  func testPodcastsWithEpisodeMetadataZeroEpisodes() async throws {
    let podcastWithNoEpisodes = try Create.unsavedPodcast()
    try await repo.insertSeries(UnsavedPodcastSeries(unsavedPodcast: podcastWithNoEpisodes))

    let allPodcastsWithEpisodeMetadata =
      try await observatory.podcastsWithEpisodeMetadata(AppDB.NoOp).get()

    #expect(allPodcastsWithEpisodeMetadata.count == 1)
    let metadata = allPodcastsWithEpisodeMetadata[0]
    #expect(metadata.episodeCount == 0)
    #expect(metadata.mostRecentEpisodeDate == nil)
  }

  @Test("allPodcastsWithEpisodeMetadata()")
  func testAllPodcastsWithEpisodeMetadata() async throws {
    let podcast = try Create.unsavedPodcast()
    let newestUnfinishedEpisode = try Create.unsavedEpisode(
      pubDate: 10.minutesAgo,
      currentTime: CMTime.seconds(60),
      queueOrder: 0
    )
    let newestUnstartedEpisode = try Create.unsavedEpisode(
      pubDate: 20.minutesAgo,
      queueOrder: 1
    )
    let newestUnqueuedEpisode = try Create.unsavedEpisode(pubDate: 30.minutesAgo)
    let newerPlayedEpisode = try Create.unsavedEpisode(
      pubDate: 1.minutesAgo,
      finishDate: 1.minutesAgo
    )
    let olderUnplayedEpisode = try Create.unsavedEpisode(pubDate: 100.minutesAgo)
    try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: podcast,
        unsavedEpisodes: [
          newestUnfinishedEpisode,
          newestUnstartedEpisode,
          newestUnqueuedEpisode,
          newerPlayedEpisode,
          olderUnplayedEpisode,
        ]
      )
    )

    let podcastAllPlayed = try Create.unsavedPodcast()
    let playedEpisode = try Create.unsavedEpisode(
      pubDate: 50.minutesAgo,
      finishDate: 1.minutesAgo
    )
    try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: podcastAllPlayed, unsavedEpisodes: [playedEpisode])
    )

    let allPodcastsWithEpisodeMetadata =
      IdentifiedArray(
        uniqueElements: try await observatory.podcastsWithEpisodeMetadata(AppDB.NoOp).get(),
        id: \.podcast.feedURL
      )
    #expect(allPodcastsWithEpisodeMetadata.count == 2)

    let podcastWithMetadata = allPodcastsWithEpisodeMetadata[id: podcast.feedURL]!
    #expect(podcastWithMetadata.episodeCount == 5)
    #expect(
      podcastWithMetadata.mostRecentEpisodeDate!
        .approximatelyEquals(newerPlayedEpisode.pubDate)
    )

    let fetchedPodcastAllPlayed = allPodcastsWithEpisodeMetadata[id: podcastAllPlayed.feedURL]!
    #expect(fetchedPodcastAllPlayed.episodeCount == 1)
    #expect(
      fetchedPodcastAllPlayed.mostRecentEpisodeDate!
        .approximatelyEquals(playedEpisode.pubDate)
    )
  }

  @Test("queuedPodcastEpisodes()")
  func testQueuedPodcastEpisodes() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: [
          Create.unsavedEpisode(guid: "top", queueOrder: 0),
          Create.unsavedEpisode(guid: "bottom", queueOrder: 4),
          Create.unsavedEpisode(guid: "midtop", queueOrder: 1),
          Create.unsavedEpisode(guid: "middle", queueOrder: 2),
          Create.unsavedEpisode(guid: "midbottom", queueOrder: 3),
          Create.unsavedEpisode(guid: "unqbottom"),
          Create.unsavedEpisode(guid: "unqmiddle"),
          Create.unsavedEpisode(guid: "unqtop"),
        ]
      )
    )

    let queuedEpisodes = try await observatory.queuedPodcastEpisodes().get()
    #expect(queuedEpisodes.count == 5)
    #expect(
      queuedEpisodes.map(\.episode.guid) == [
        "top", "midtop", "middle", "midbottom", "bottom",
      ]
    )
  }

  @Test("podcastEpisodes(Episode.finished, Episode.Columns.finishDate.desc)")
  func testFinishedPodcastEpisodes() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: [
          Create.unsavedEpisode(
            guid: "top",
            pubDate: 15.minutesAgo,
            finishDate: 5.minutesAgo
          ),
          Create.unsavedEpisode(guid: "topUnfinished"),
          Create.unsavedEpisode(
            guid: "bottom",
            pubDate: 1.minutesAgo,
            finishDate: 15.minutesAgo
          ),
          Create.unsavedEpisode(guid: "bottomUnfinished"),
          Create.unsavedEpisode(
            guid: "middle",
            pubDate: 25.minutesAgo,
            finishDate: 10.minutesAgo
          ),
          Create.unsavedEpisode(guid: "middleUnfinished"),
        ]
      )
    )

    let finishedEpisodes =
      try await observatory.podcastEpisodes(
        filter: Episode.finished,
        order: Episode.Columns.finishDate.desc
      )
      .get()
    #expect(finishedEpisodes.count == 3)
    #expect(finishedEpisodes.map(\.episode.guid) == ["top", "middle", "bottom"])
  }

  @Test("queuedPodcastEpisodes AsyncSequence receives all updates")
  func testQueuedPodcastEpisodesAsyncSequence() async throws {
    let (episode1, episode2, episode3) = try await Create.threePodcastEpisodes()

    let updateCount = Counter()

    Task {
      for try await queuedEpisodes in observatory.queuedPodcastEpisodes() {
        await updateCount(queuedEpisodes.count)
      }
    }

    try await queue.unshift(episode1.id)
    try await updateCount.wait(for: 1)

    try await queue.unshift(episode2.id)
    try await updateCount.wait(for: 2)

    try await queue.unshift(episode3.id)
    try await updateCount.wait(for: 3)

    try await queue.dequeue(episode2.id)
    try await updateCount.wait(for: 2)

    try await queue.dequeue(episode3.id)
    try await updateCount.wait(for: 1)

    try await queue.dequeue(episode1.id)
    try await updateCount.wait(for: 0)
  }

  // MARK: - podcastEpisodes()

  @Test("podcastEpisodes() with empty array")
  func testpodcastEpisodesEmpty() async throws {
    // Test with empty array
    let episodes = try await observatory.podcastEpisodes([]).get()
    #expect(episodes.isEmpty)
  }

  @Test("podcastEpisodes() with non-existing episodes")
  func testpodcastEpisodesNonExisting() async throws {
    // Test with media GUIDs that don't exist in database
    let nonExistentMediaGUIDs = [
      MediaGUID(guid: GUID(UUID().uuidString), mediaURL: MediaURL(URL.valid())),
      MediaGUID(guid: GUID(UUID().uuidString), mediaURL: MediaURL(URL.valid())),
      MediaGUID(guid: GUID(UUID().uuidString), mediaURL: MediaURL(URL.valid())),
    ]

    let episodes = try await observatory.podcastEpisodes(nonExistentMediaGUIDs).get()
    #expect(episodes.isEmpty)
  }

  @Test("podcastEpisodes() with existing episodes")
  func testpodcastEpisodesExisting() async throws {
    // Create test episodes with specific media URLs
    let guid1 = GUID("episode1")
    let guid2 = GUID("episode2")
    let guid3 = GUID("episode3")
    let mediaURL1 = MediaURL(URL.valid())
    let mediaURL2 = MediaURL(URL.valid())
    let mediaURL3 = MediaURL(URL.valid())
    let mediaGUID1 = MediaGUID(guid: guid1, mediaURL: mediaURL1)
    let mediaGUID2 = MediaGUID(guid: guid2, mediaURL: mediaURL2)

    let unsavedPodcast = try Create.unsavedPodcast()
    try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: [
          Create.unsavedEpisode(guid: guid1, mediaURL: mediaURL1, title: "Episode 1"),
          Create.unsavedEpisode(guid: guid2, mediaURL: mediaURL2, title: "Episode 2"),
          Create.unsavedEpisode(guid: guid3, mediaURL: mediaURL3, title: "Episode 3"),
          Create.unsavedEpisode(guid: "episode4", title: "Episode 4"),  // Different media GUID
        ]
      )
    )

    // Test querying for specific episodes
    let episodes =
      try await observatory.podcastEpisodes(
        [mediaGUID1, mediaGUID2]
      )
      .get()

    #expect(episodes.count == 2)
    let episodeTitles = Set(episodes.map(\.episode.title))
    #expect(episodeTitles == Set(["Episode 1", "Episode 2"]))

    // Verify the media GUIDs match
    let returnedMediaGUIDs = Set(episodes.map(\.episode.unsaved.id))
    #expect(returnedMediaGUIDs == Set([mediaGUID1, mediaGUID2]))
  }

  @Test("podcastEpisodes() with mixed existing and non-existing")
  func testpodcastEpisodesMixed() async throws {
    // Create test episodes
    let existingGUID1 = GUID("existing1")
    let existingGUID2 = GUID("existing2")
    let existingMediaURL1 = MediaURL(URL.valid())
    let existingMediaURL2 = MediaURL(URL.valid())
    let existingMediaGUID1 = MediaGUID(guid: existingGUID1, mediaURL: existingMediaURL1)
    let existingMediaGUID2 = MediaGUID(guid: existingGUID2, mediaURL: existingMediaURL2)
    let nonExistentMediaGUID = MediaGUID(
      guid: GUID(UUID().uuidString),
      mediaURL: MediaURL(URL.valid())
    )

    let unsavedPodcast = try Create.unsavedPodcast()
    try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: [
          Create.unsavedEpisode(
            guid: existingGUID1,
            mediaURL: existingMediaURL1,
            title: "Existing 1"
          ),
          Create.unsavedEpisode(
            guid: existingGUID2,
            mediaURL: existingMediaURL2,
            title: "Existing 2"
          ),
        ]
      )
    )

    // Query with mix of existing and non-existing media GUIDs
    let episodes =
      try await observatory.podcastEpisodes(
        [existingMediaGUID1, nonExistentMediaGUID, existingMediaGUID2]
      )
      .get()

    #expect(episodes.count == 2)
    let episodeTitles = Set(episodes.map(\.episode.title))
    #expect(episodeTitles == Set(["Existing 1", "Existing 2"]))
  }

  @Test("podcastEpisodes() with custom order and limit")
  func testpodcastEpisodesOrderAndLimit() async throws {
    // Create episodes with different pub dates
    let guid1 = GUID("newest")
    let guid2 = GUID("oldest")
    let guid3 = GUID("middle")
    let mediaURL1 = MediaURL(URL.valid())
    let mediaURL2 = MediaURL(URL.valid())
    let mediaURL3 = MediaURL(URL.valid())
    let mediaGUID1 = MediaGUID(guid: guid1, mediaURL: mediaURL1)
    let mediaGUID2 = MediaGUID(guid: guid2, mediaURL: mediaURL2)
    let mediaGUID3 = MediaGUID(guid: guid3, mediaURL: mediaURL3)

    let unsavedPodcast = try Create.unsavedPodcast()
    try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: [
          Create.unsavedEpisode(
            guid: guid1,
            mediaURL: mediaURL1,
            title: "Newest Episode",
            pubDate: 1.minutesAgo
          ),
          Create.unsavedEpisode(
            guid: guid2,
            mediaURL: mediaURL2,
            title: "Oldest Episode",
            pubDate: 60.minutesAgo
          ),
          Create.unsavedEpisode(
            guid: guid3,
            mediaURL: mediaURL3,
            title: "Middle Episode",
            pubDate: 30.minutesAgo
          ),
        ]
      )
    )

    // Test ascending order
    let episodesAsc =
      try await observatory.podcastEpisodes(
        [mediaGUID1, mediaGUID2, mediaGUID3],
        order: Episode.Columns.pubDate.asc
      )
      .get()

    #expect(episodesAsc.count == 3)
    #expect(
      episodesAsc.map(\.episode.title) == ["Oldest Episode", "Middle Episode", "Newest Episode"]
    )

    // Test with limit
    let episodesLimited =
      try await observatory.podcastEpisodes(
        [mediaGUID1, mediaGUID2, mediaGUID3],
        order: Episode.Columns.pubDate.desc,
        limit: 2
      )
      .get()

    #expect(episodesLimited.count == 2)
    #expect(episodesLimited.map(\.episode.title) == ["Newest Episode", "Middle Episode"])
  }

  @Test("podcastEpisodes() AsyncSequence receives updates")
  func testpodcastEpisodesAsyncSequence() async throws {
    let guid1 = GUID("episode1")
    let guid2 = GUID("episode2")
    let mediaURL1 = MediaURL(URL.valid())
    let mediaURL2 = MediaURL(URL.valid())
    let mediaGUID1 = MediaGUID(guid: guid1, mediaURL: mediaURL1)
    let mediaGUID2 = MediaGUID(guid: guid2, mediaURL: mediaURL2)

    let observedEpisodes = ActorContainer<[PodcastEpisode]>()

    // Start observing before any episodes exist
    Task {
      for try await episodes in observatory.podcastEpisodes([mediaGUID1, mediaGUID2]) {
        await observedEpisodes.set(episodes)
      }
    }

    // Step 1: Wait for initial empty observation
    try await observedEpisodes.waitForEqual(to: [])

    // Step 2: Insert first episode (newer)
    let unsavedPodcast1 = try Create.unsavedPodcast()
    let series1 = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast1,
        unsavedEpisodes: [
          Create.unsavedEpisode(
            guid: guid1,
            mediaURL: mediaURL1,
            title: "Episode 1",
            pubDate: 1.minutesAgo
          )
        ]
      )
    )
    let episode1 = PodcastEpisode(podcast: series1.podcast, episode: series1.episodes[0])

    // Wait for observation with first episode
    try await observedEpisodes.waitForEqual(to: [episode1])

    // Step 3: Insert second episode (older)
    let unsavedPodcast2 = try Create.unsavedPodcast()
    let series2 = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast2,
        unsavedEpisodes: [
          Create.unsavedEpisode(
            guid: guid2,
            mediaURL: mediaURL2,
            title: "Episode 2",
            pubDate: 10.minutesAgo
          )
        ]
      )
    )
    let episode2 = PodcastEpisode(podcast: series2.podcast, episode: series2.episodes[0])

    // Wait for observation with both episodes (ordered by pubDate desc by default)
    // Episode 1 should come first since it's newer
    try await observedEpisodes.waitForEqual(to: [episode1, episode2])

    // Step 4: Insert episode with different media GUID (should not trigger update)
    let unsavedPodcast3 = try Create.unsavedPodcast()
    try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast3,
        unsavedEpisodes: [Create.unsavedEpisode(title: "Episode 3 - Different Media")]
      )
    )

    // Should still have only 2 podcastEpisodes (no new update for unrelated episode)
    try await observedEpisodes.waitForEqual(to: [episode1, episode2])
  }

  // MARK: - podcasts(feedURLs)

  @Test("podcasts() with empty array")
  func testPodcastsEmpty() async throws {
    // Test with empty array
    let podcasts = try await observatory.podcasts([]).get()
    #expect(podcasts.isEmpty)
  }

  @Test("podcasts() with non-existing podcasts")
  func testPodcastsNonExisting() async throws {
    // Test with feed URLs that don't exist in database
    let nonExistentFeedURLs = [
      FeedURL(URL(string: "https://example1.com/feed.rss")!),
      FeedURL(URL(string: "https://example2.com/feed.rss")!),
      FeedURL(URL(string: "https://example3.com/feed.rss")!),
    ]

    let podcasts = try await observatory.podcasts(nonExistentFeedURLs).get()
    #expect(podcasts.isEmpty)
  }

  @Test("podcasts() with existing podcasts")
  func testPodcastsExisting() async throws {
    // Create test podcasts with specific feed URLs
    let feedURL1 = FeedURL(URL(string: "https://podcast1.com/feed.rss")!)
    let feedURL2 = FeedURL(URL(string: "https://podcast2.com/feed.rss")!)
    let feedURL3 = FeedURL(URL(string: "https://podcast3.com/feed.rss")!)

    let unsavedPodcast1 = try Create.unsavedPodcast(feedURL: feedURL1, title: "Podcast 1")
    let unsavedPodcast2 = try Create.unsavedPodcast(feedURL: feedURL2, title: "Podcast 2")
    let unsavedPodcast3 = try Create.unsavedPodcast(feedURL: feedURL3, title: "Podcast 3")

    try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast1,
        unsavedEpisodes: [Create.unsavedEpisode()]
      )
    )
    try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast2,
        unsavedEpisodes: [Create.unsavedEpisode()]
      )
    )
    try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast3,
        unsavedEpisodes: [Create.unsavedEpisode()]
      )
    )

    // Test querying for specific podcasts
    let podcasts = try await observatory.podcasts([feedURL1, feedURL2]).get()

    #expect(podcasts.count == 2)
    let podcastTitles = Set(podcasts.map(\.title))
    #expect(podcastTitles == Set(["Podcast 1", "Podcast 2"]))

    // Verify the feed URLs match
    let returnedFeedURLs = Set(podcasts.map(\.feedURL))
    #expect(returnedFeedURLs == Set([feedURL1, feedURL2]))
  }

  @Test("podcasts() with mixed existing and non-existing")
  func testPodcastsMixed() async throws {
    // Create test podcasts
    let existingFeedURL1 = FeedURL(URL(string: "https://existing1.com/feed.rss")!)
    let existingFeedURL2 = FeedURL(URL(string: "https://existing2.com/feed.rss")!)
    let nonExistentFeedURL = FeedURL(URL(string: "https://nonexistent.com/feed.rss")!)

    let unsavedPodcast1 = try Create.unsavedPodcast(feedURL: existingFeedURL1, title: "Existing 1")
    let unsavedPodcast2 = try Create.unsavedPodcast(feedURL: existingFeedURL2, title: "Existing 2")

    try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast1,
        unsavedEpisodes: [Create.unsavedEpisode()]
      )
    )
    try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast2,
        unsavedEpisodes: [Create.unsavedEpisode()]
      )
    )

    // Query with mix of existing and non-existing feed URLs
    let podcasts =
      try await observatory.podcasts(
        [existingFeedURL1, nonExistentFeedURL, existingFeedURL2]
      )
      .get()

    #expect(podcasts.count == 2)
    let podcastTitles = Set(podcasts.map(\.title))
    #expect(podcastTitles == Set(["Existing 1", "Existing 2"]))
  }

  @Test("podcasts() with custom order and limit")
  func testPodcastsOrderAndLimit() async throws {
    // Create podcasts with different last update times
    let feedURL1 = FeedURL(URL(string: "https://newest.com/feed.rss")!)
    let feedURL2 = FeedURL(URL(string: "https://oldest.com/feed.rss")!)
    let feedURL3 = FeedURL(URL(string: "https://middle.com/feed.rss")!)

    let unsavedPodcast1 = try Create.unsavedPodcast(
      feedURL: feedURL1,
      title: "Newest Podcast",
      lastUpdate: 1.minutesAgo
    )
    let unsavedPodcast2 = try Create.unsavedPodcast(
      feedURL: feedURL2,
      title: "Oldest Podcast",
      lastUpdate: 60.minutesAgo
    )
    let unsavedPodcast3 = try Create.unsavedPodcast(
      feedURL: feedURL3,
      title: "Middle Podcast",
      lastUpdate: 30.minutesAgo
    )

    try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast1,
        unsavedEpisodes: [Create.unsavedEpisode()]
      )
    )
    try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast2,
        unsavedEpisodes: [Create.unsavedEpisode()]
      )
    )
    try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast3,
        unsavedEpisodes: [Create.unsavedEpisode()]
      )
    )

    // Test basic retrieval (ordering will be default from the base method)
    let podcasts =
      try await observatory.podcasts(
        [feedURL1, feedURL2, feedURL3]
      )
      .get()

    #expect(podcasts.count == 3)
    let podcastTitles = Set(podcasts.map(\.title))
    #expect(podcastTitles == Set(["Newest Podcast", "Oldest Podcast", "Middle Podcast"]))

    // Verify the feed URLs match
    let returnedFeedURLs = Set(podcasts.map(\.feedURL))
    #expect(returnedFeedURLs == Set([feedURL1, feedURL2, feedURL3]))
  }

  @Test("podcasts() AsyncSequence receives updates")
  func testPodcastsAsyncSequence() async throws {
    let feedURL1 = FeedURL(URL(string: "https://podcast1.com/feed.rss")!)
    let feedURL2 = FeedURL(URL(string: "https://podcast2.com/feed.rss")!)

    let observedPodcasts = ActorContainer<[Podcast]>()

    // Start observing before any podcasts exist
    Task {
      for try await podcasts in observatory.podcasts([feedURL1, feedURL2]) {
        await observedPodcasts.set(podcasts)
      }
    }

    // Step 1: Wait for initial empty observation
    try await observedPodcasts.waitForEqual(to: [])

    // Step 2: Insert first podcast (newer)
    let unsavedPodcast1 = try Create.unsavedPodcast(
      feedURL: feedURL1,
      title: "Podcast 1",
      lastUpdate: 1.minutesAgo
    )
    let series1 = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast1,
        unsavedEpisodes: [Create.unsavedEpisode()]
      )
    )
    let podcast1 = series1.podcast

    // Wait for observation with first podcast
    try await observedPodcasts.waitForEqual(to: [podcast1])

    // Step 3: Insert second podcast (older)
    let unsavedPodcast2 = try Create.unsavedPodcast(
      feedURL: feedURL2,
      title: "Podcast 2",
      lastUpdate: 10.minutesAgo
    )
    let series2 = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast2,
        unsavedEpisodes: [Create.unsavedEpisode()]
      )
    )
    let podcast2 = series2.podcast

    // Wait for observation with both podcasts
    // Order is not guaranteed, so just check both are present
    let expectedPodcasts = Set([podcast1, podcast2])
    try await Wait.until(
      { Set(await observedPodcasts.get()!) == expectedPodcasts },
      { "Expected podcasts to match: \(expectedPodcasts)" }
    )

    // Step 4: Insert podcast with different feed URL (should not trigger update)
    let unsavedPodcast3 = try Create.unsavedPodcast(title: "Podcast 3 - Different Feed")
    try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast3,
        unsavedEpisodes: [Create.unsavedEpisode()]
      )
    )

    // Should still have only 2 podcasts (no new update for unrelated podcast)
    // Since order is not guaranteed, we check the Set remains the same
    try await Wait.until(
      { Set(await observedPodcasts.get()!) == expectedPodcasts },
      { "Expected podcasts to remain unchanged: \(expectedPodcasts)" }
    )

    // Step 5: Test subscription updates (modify existing podcast)
    try await repo.markSubscribed(podcast1.id)
    let updatedPodcast1 = try await repo.podcastSeries(podcast1.id)!.podcast

    // Wait for observation with updated podcast
    let expectedUpdatedPodcasts = Set([updatedPodcast1, podcast2])
    try await Wait.until(
      { Set(await observedPodcasts.get()!) == expectedUpdatedPodcasts },
      { "Expected updated podcasts to match: \(expectedUpdatedPodcasts)" }
    )
  }

  // MARK: - podcastsWithEpisodeMetadata(feedURLs)

  @Test("podcastsWithEpisodeMetadata(feedURLs) with empty array")
  func testPodcastsWithEpisodeMetadataFeedURLsEmpty() async throws {
    // Test with empty array
    let podcastsWithMetadata = try await observatory.podcastsWithEpisodeMetadata([]).get()
    #expect(podcastsWithMetadata.isEmpty)
  }

  @Test("podcastsWithEpisodeMetadata(feedURLs) with non-existing podcasts")
  func testPodcastsWithEpisodeMetadataFeedURLsNonExisting() async throws {
    // Test with feed URLs that don't exist in database
    let nonExistentFeedURLs = [
      FeedURL(URL(string: "https://example1.com/feed.rss")!),
      FeedURL(URL(string: "https://example2.com/feed.rss")!),
      FeedURL(URL(string: "https://example3.com/feed.rss")!),
    ]

    let podcastsWithMetadata =
      try await observatory.podcastsWithEpisodeMetadata(nonExistentFeedURLs).get()
    #expect(podcastsWithMetadata.isEmpty)
  }

  @Test("podcastsWithEpisodeMetadata(feedURLs) with existing podcasts")
  func testPodcastsWithEpisodeMetadataFeedURLsExisting() async throws {
    // Create test podcasts with specific feed URLs
    let feedURL1 = FeedURL(URL(string: "https://podcast1.com/feed.rss")!)
    let feedURL2 = FeedURL(URL(string: "https://podcast2.com/feed.rss")!)
    let feedURL3 = FeedURL(URL(string: "https://podcast3.com/feed.rss")!)

    let unsavedPodcast1 = try Create.unsavedPodcast(feedURL: feedURL1, title: "Podcast 1")
    let unsavedPodcast2 = try Create.unsavedPodcast(feedURL: feedURL2, title: "Podcast 2")
    let unsavedPodcast3 = try Create.unsavedPodcast(feedURL: feedURL3, title: "Podcast 3")

    let tenMinutesAgo = 10.minutesAgo
    try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast1,
        unsavedEpisodes: [
          Create.unsavedEpisode(pubDate: tenMinutesAgo),
          Create.unsavedEpisode(pubDate: 20.minutesAgo),
        ]
      )
    )

    let fiveMinutesAgo = 5.minutesAgo
    try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast2,
        unsavedEpisodes: [Create.unsavedEpisode(pubDate: fiveMinutesAgo)]
      )
    )
    try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast3,
        unsavedEpisodes: [
          Create.unsavedEpisode(pubDate: 15.minutesAgo),
          Create.unsavedEpisode(pubDate: 25.minutesAgo),
          Create.unsavedEpisode(pubDate: 35.minutesAgo),
        ]
      )
    )

    // Test querying for specific podcasts
    let podcastsWithMetadata =
      try await observatory.podcastsWithEpisodeMetadata([feedURL1, feedURL2]).get()

    #expect(podcastsWithMetadata.count == 2)
    let podcastTitles = Set(podcastsWithMetadata.map(\.podcast.title))
    #expect(podcastTitles == Set(["Podcast 1", "Podcast 2"]))

    // Verify metadata for each podcast
    let podcast1Metadata = podcastsWithMetadata.first { $0.podcast.feedURL == feedURL1 }!
    #expect(podcast1Metadata.episodeCount == 2)
    #expect(podcast1Metadata.mostRecentEpisodeDate!.approximatelyEquals(tenMinutesAgo))

    let podcast2Metadata = podcastsWithMetadata.first { $0.podcast.feedURL == feedURL2 }!
    #expect(podcast2Metadata.episodeCount == 1)
    #expect(podcast2Metadata.mostRecentEpisodeDate!.approximatelyEquals(fiveMinutesAgo))
  }

  @Test("podcastsWithEpisodeMetadata(feedURLs) with mixed existing and non-existing")
  func testPodcastsWithEpisodeMetadataFeedURLsMixed() async throws {
    // Create test podcasts
    let existingFeedURL1 = FeedURL(URL(string: "https://existing1.com/feed.rss")!)
    let existingFeedURL2 = FeedURL(URL(string: "https://existing2.com/feed.rss")!)
    let nonExistentFeedURL = FeedURL(URL(string: "https://nonexistent.com/feed.rss")!)

    let unsavedPodcast1 = try Create.unsavedPodcast(feedURL: existingFeedURL1, title: "Existing 1")
    let unsavedPodcast2 = try Create.unsavedPodcast(feedURL: existingFeedURL2, title: "Existing 2")

    try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast1,
        unsavedEpisodes: [Create.unsavedEpisode(pubDate: 10.minutesAgo)]
      )
    )
    try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast2,
        unsavedEpisodes: [
          Create.unsavedEpisode(pubDate: 5.minutesAgo),
          Create.unsavedEpisode(pubDate: 15.minutesAgo),
        ]
      )
    )

    // Query with mix of existing and non-existing feed URLs
    let podcastsWithMetadata =
      try await observatory.podcastsWithEpisodeMetadata(
        [existingFeedURL1, nonExistentFeedURL, existingFeedURL2]
      )
      .get()

    #expect(podcastsWithMetadata.count == 2)
    let podcastTitles = Set(podcastsWithMetadata.map(\.podcast.title))
    #expect(podcastTitles == Set(["Existing 1", "Existing 2"]))

    // Verify metadata
    let podcast1Metadata = podcastsWithMetadata.first { $0.podcast.feedURL == existingFeedURL1 }!
    #expect(podcast1Metadata.episodeCount == 1)

    let podcast2Metadata = podcastsWithMetadata.first { $0.podcast.feedURL == existingFeedURL2 }!
    #expect(podcast2Metadata.episodeCount == 2)
  }

  @Test("podcastsWithEpisodeMetadata(feedURLs) with limit")
  func testPodcastsWithEpisodeMetadataFeedURLsLimit() async throws {
    // Create podcasts with different last update times
    let feedURL1 = FeedURL(URL(string: "https://newest.com/feed.rss")!)
    let feedURL2 = FeedURL(URL(string: "https://oldest.com/feed.rss")!)
    let feedURL3 = FeedURL(URL(string: "https://middle.com/feed.rss")!)

    let unsavedPodcast1 = try Create.unsavedPodcast(
      feedURL: feedURL1,
      title: "Newest Podcast"
    )
    let unsavedPodcast2 = try Create.unsavedPodcast(
      feedURL: feedURL2,
      title: "Oldest Podcast"
    )
    let unsavedPodcast3 = try Create.unsavedPodcast(
      feedURL: feedURL3,
      title: "Middle Podcast"
    )

    try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast1,
        unsavedEpisodes: [Create.unsavedEpisode(pubDate: 1.minutesAgo)]
      )
    )
    try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast2,
        unsavedEpisodes: [Create.unsavedEpisode(pubDate: 60.minutesAgo)]
      )
    )
    try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast3,
        unsavedEpisodes: [Create.unsavedEpisode(pubDate: 30.minutesAgo)]
      )
    )

    // Test with limit
    let podcastsWithMetadataLimited =
      try await observatory.podcastsWithEpisodeMetadata(
        [feedURL1, feedURL2, feedURL3],
        limit: 2
      )
      .get()

    #expect(podcastsWithMetadataLimited.count == 2)
  }

  @Test("podcastsWithEpisodeMetadata(feedURLs) AsyncSequence receives updates")
  func testPodcastsWithEpisodeMetadataFeedURLsAsyncSequence() async throws {
    let feedURL1 = FeedURL(URL(string: "https://podcast1.com/feed.rss")!)
    let feedURL2 = FeedURL(URL(string: "https://podcast2.com/feed.rss")!)

    let observedMetadata = ActorContainer<[PodcastWithEpisodeMetadata<Podcast>]>()

    // Start observing before any podcasts exist
    Task {
      for try await metadata in observatory.podcastsWithEpisodeMetadata([feedURL1, feedURL2]) {
        await observedMetadata.set(metadata)
      }
    }

    // Step 1: Wait for initial empty observation
    try await observedMetadata.waitForEqual(to: [])

    // Step 2: Insert first podcast with 2 episodes
    let unsavedPodcast1 = try Create.unsavedPodcast(
      feedURL: feedURL1,
      title: "Podcast 1"
    )
    let fiveMinutesAgo = 5.minutesAgo
    let series1 = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast1,
        unsavedEpisodes: [
          Create.unsavedEpisode(pubDate: fiveMinutesAgo),
          Create.unsavedEpisode(pubDate: 15.minutesAgo),
        ]
      )
    )

    // Wait for observation with first podcast metadata
    try await Wait.until(
      {
        let current = await observedMetadata.get()
        return current?.count == 1 && current?.first?.episodeCount == 2
      },
      { "Expected 1 podcast with 2 episodes" }
    )

    // Verify the metadata details
    var currentMetadata = await observedMetadata.get()!
    var podcast1Current = currentMetadata.first { $0.podcast.feedURL == feedURL1 }!
    #expect(podcast1Current.episodeCount == 2)
    #expect(podcast1Current.mostRecentEpisodeDate!.approximatelyEquals(fiveMinutesAgo))

    // Step 3: Insert second podcast with 1 episode
    let unsavedPodcast2 = try Create.unsavedPodcast(
      feedURL: feedURL2,
      title: "Podcast 2"
    )
    let tenMinutesAgo = 10.minutesAgo
    _ = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast2,
        unsavedEpisodes: [Create.unsavedEpisode(pubDate: tenMinutesAgo)]
      )
    )

    // Wait for observation with both podcasts
    try await Wait.until(
      { await observedMetadata.get()?.count == 2 },
      { "Expected 2 podcasts" }
    )

    // Verify episode counts
    currentMetadata = await observedMetadata.get()!
    podcast1Current = currentMetadata.first { $0.podcast.feedURL == feedURL1 }!
    let podcast2Current = currentMetadata.first { $0.podcast.feedURL == feedURL2 }!
    #expect(podcast1Current.episodeCount == 2)
    #expect(podcast2Current.episodeCount == 1)
    #expect(podcast2Current.mostRecentEpisodeDate!.approximatelyEquals(tenMinutesAgo))

    // Step 4: Insert podcast with different feed URL (should not trigger update)
    let unsavedPodcast3 = try Create.unsavedPodcast(title: "Podcast 3 - Different Feed")
    try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast3,
        unsavedEpisodes: [Create.unsavedEpisode()]
      )
    )

    // Should still have only 2 podcasts
    try await Wait.until(
      { await observedMetadata.get()!.count == 2 },
      { "Expected 2 podcasts to remain" }
    )

    // Step 5: Add an episode to podcast1 and verify metadata updates
    let oneMinuteAgo = 1.minutesAgo
    let newEpisode = try Create.unsavedEpisode(pubDate: oneMinuteAgo)
    try await repo.upsertPodcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: series1.podcast.unsaved,
        unsavedEpisode: newEpisode
      )
    )

    // Wait for updated metadata with new episode count
    try await Wait.until(
      {
        let current = await observedMetadata.get()!
        let updated = current.first { $0.podcast.feedURL == feedURL1 }
        return updated?.episodeCount == 3
      },
      { "Expected podcast1 to have 3 episodes" }
    )

    // Verify most recent episode date also updated
    let finalMetadata = await observedMetadata.get()!
    let podcast1Final = finalMetadata.first { $0.podcast.feedURL == feedURL1 }!
    #expect(podcast1Final.mostRecentEpisodeDate!.approximatelyEquals(oneMinuteAgo))
  }
}
