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

  @Test("allPodcastsWithLatestEpisodeDates()")
  func testAllPodcastsWithLatestEpisodeDates() async throws {
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
      completionDate: 1.minutesAgo
    )
    let olderUnplayedEpisode = try Create.unsavedEpisode(pubDate: 100.minutesAgo)
    try await repo.insertSeries(
      podcast,
      unsavedEpisodes: [
        newestUnfinishedEpisode,
        newestUnstartedEpisode,
        newestUnqueuedEpisode,
        newerPlayedEpisode,
        olderUnplayedEpisode,
      ]
    )

    let podcastAllPlayed = try Create.unsavedPodcast()
    let playedEpisode = try Create.unsavedEpisode(completionDate: 1.minutesAgo)
    try await repo.insertSeries(podcastAllPlayed, unsavedEpisodes: [playedEpisode])

    let allPodcastsWithLatestEpisodeDates =
      IdentifiedArray(
        uniqueElements: try await observatory.podcastsWithLatestEpisodeDates(AppDB.NoOp).get(),
        id: \.podcast.feedURL
      )
    #expect(allPodcastsWithLatestEpisodeDates.count == 2)

    let podcastWithLatestEpisodes = allPodcastsWithLatestEpisodeDates[id: podcast.feedURL]!
    #expect(
      podcastWithLatestEpisodes.maxUnfinishedEpisodePubDate!
        .approximatelyEquals(newestUnfinishedEpisode.pubDate)
    )
    #expect(
      podcastWithLatestEpisodes.maxUnstartedEpisodePubDate!
        .approximatelyEquals(newestUnstartedEpisode.pubDate)
    )
    #expect(
      podcastWithLatestEpisodes.maxUnqueuedEpisodePubDate!
        .approximatelyEquals(newestUnqueuedEpisode.pubDate)
    )

    let fetchedPodcastAllPlayed = allPodcastsWithLatestEpisodeDates[id: podcastAllPlayed.feedURL]!
    #expect(fetchedPodcastAllPlayed.maxUnfinishedEpisodePubDate == nil)
    #expect(fetchedPodcastAllPlayed.maxUnstartedEpisodePubDate == nil)
    #expect(fetchedPodcastAllPlayed.maxUnqueuedEpisodePubDate == nil)
  }

  @Test("queuedPodcastEpisodes() and queuedEpisodeIDs")
  func testQueuedPodcastEpisodesAndIDs() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    try await repo.insertSeries(
      unsavedPodcast,
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

    let queuedEpisodes = try await observatory.queuedPodcastEpisodes().get()
    #expect(queuedEpisodes.count == 5)
    #expect(
      queuedEpisodes.map(\.episode.guid) == [
        "top", "midtop", "middle", "midbottom", "bottom",
      ]
    )

    let queuedEpisodeIDs = try await observatory.queuedEpisodeIDs().get()
    #expect(queuedEpisodes.count == 5)
    #expect(queuedEpisodeIDs == Set(queuedEpisodes.map(\.id)))
  }

  @Test("podcastEpisodes(Episode.finished, Episode.Columns.completionDate.desc)")
  func testFinishedPodcastEpisodes() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [
        Create.unsavedEpisode(
          guid: "top",
          pubDate: 15.minutesAgo,
          completionDate: 5.minutesAgo
        ),
        Create.unsavedEpisode(guid: "topUnfinished"),
        Create.unsavedEpisode(
          guid: "bottom",
          pubDate: 1.minutesAgo,
          completionDate: 15.minutesAgo
        ),
        Create.unsavedEpisode(guid: "bottomUnfinished"),
        Create.unsavedEpisode(
          guid: "middle",
          pubDate: 25.minutesAgo,
          completionDate: 10.minutesAgo
        ),
        Create.unsavedEpisode(guid: "middleUnfinished"),
      ]
    )

    let finishedEpisodes =
      try await observatory.podcastEpisodes(
        filter: Episode.finished,
        order: Episode.Columns.completionDate.desc
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

  @Test("maxQueuePosition()")
  func testMaxQueuePosition() async throws {
    // Test when no episodes are queued
    var maxPosition = try await observatory.maxQueuePosition().get()
    #expect(maxPosition == nil)

    let (episode1, episode2, episode3) = try await Create.threePodcastEpisodes()

    // Add episodes to queue using queue methods
    try await queue.unshift(episode1.id)  // Position 0
    maxPosition = try await observatory.maxQueuePosition().get()
    #expect(maxPosition == 0)

    try await queue.append(episode2.id)  // Position 1
    maxPosition = try await observatory.maxQueuePosition().get()
    #expect(maxPosition == 1)

    try await queue.append(episode3.id)  // Position 2
    maxPosition = try await observatory.maxQueuePosition().get()
    #expect(maxPosition == 2)
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
      unsavedPodcast,
      unsavedEpisodes: [
        Create.unsavedEpisode(guid: guid1, mediaURL: mediaURL1, title: "Episode 1"),
        Create.unsavedEpisode(guid: guid2, mediaURL: mediaURL2, title: "Episode 2"),
        Create.unsavedEpisode(guid: guid3, mediaURL: mediaURL3, title: "Episode 3"),
        Create.unsavedEpisode(guid: "episode4", title: "Episode 4"),  // Different media GUID
      ]
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
      unsavedPodcast,
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
      unsavedPodcast,
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
      unsavedPodcast1,
      unsavedEpisodes: [
        Create.unsavedEpisode(
          guid: guid1,
          mediaURL: mediaURL1,
          title: "Episode 1",
          pubDate: 1.minutesAgo
        )
      ]
    )
    let episode1 = PodcastEpisode(podcast: series1.podcast, episode: series1.episodes[0])

    // Wait for observation with first episode
    try await observedEpisodes.waitForEqual(to: [episode1])

    // Step 3: Insert second episode (older)
    let unsavedPodcast2 = try Create.unsavedPodcast()
    let series2 = try await repo.insertSeries(
      unsavedPodcast2,
      unsavedEpisodes: [
        Create.unsavedEpisode(
          guid: guid2,
          mediaURL: mediaURL2,
          title: "Episode 2",
          pubDate: 10.minutesAgo
        )
      ]
    )
    let episode2 = PodcastEpisode(podcast: series2.podcast, episode: series2.episodes[0])

    // Wait for observation with both episodes (ordered by pubDate desc by default)
    // Episode 1 should come first since it's newer
    try await observedEpisodes.waitForEqual(to: [episode1, episode2])

    // Step 4: Insert episode with different media GUID (should not trigger update)
    let unsavedPodcast3 = try Create.unsavedPodcast()
    try await repo.insertSeries(
      unsavedPodcast3,
      unsavedEpisodes: [Create.unsavedEpisode(title: "Episode 3 - Different Media")]
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

    try await repo.insertSeries(unsavedPodcast1, unsavedEpisodes: [Create.unsavedEpisode()])
    try await repo.insertSeries(unsavedPodcast2, unsavedEpisodes: [Create.unsavedEpisode()])
    try await repo.insertSeries(unsavedPodcast3, unsavedEpisodes: [Create.unsavedEpisode()])

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

    try await repo.insertSeries(unsavedPodcast1, unsavedEpisodes: [Create.unsavedEpisode()])
    try await repo.insertSeries(unsavedPodcast2, unsavedEpisodes: [Create.unsavedEpisode()])

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

    try await repo.insertSeries(unsavedPodcast1, unsavedEpisodes: [Create.unsavedEpisode()])
    try await repo.insertSeries(unsavedPodcast2, unsavedEpisodes: [Create.unsavedEpisode()])
    try await repo.insertSeries(unsavedPodcast3, unsavedEpisodes: [Create.unsavedEpisode()])

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
      unsavedPodcast1,
      unsavedEpisodes: [Create.unsavedEpisode()]
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
      unsavedPodcast2,
      unsavedEpisodes: [Create.unsavedEpisode()]
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
      unsavedPodcast3,
      unsavedEpisodes: [Create.unsavedEpisode()]
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
}
