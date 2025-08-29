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
        uniqueElements: try await observatory.allPodcastsWithLatestEpisodeDates().get(),
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

  @Test("queuedPodcastEpisodes()")
  func testQueuedPodcastEpisodes() async throws {
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
  }

  @Test("podcastEpisodes(Episode.completed, Episode.Columns.completionDate.desc)")
  func testCompletedPodcastEpisodes() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [
        Create.unsavedEpisode(
          guid: "top",
          pubDate: 15.minutesAgo,
          completionDate: 5.minutesAgo
        ),
        Create.unsavedEpisode(guid: "topUncompleted"),
        Create.unsavedEpisode(
          guid: "bottom",
          pubDate: 1.minutesAgo,
          completionDate: 15.minutesAgo
        ),
        Create.unsavedEpisode(guid: "bottomUncompleted"),
        Create.unsavedEpisode(
          guid: "middle",
          pubDate: 25.minutesAgo,
          completionDate: 10.minutesAgo
        ),
        Create.unsavedEpisode(guid: "middleUncompleted"),
      ]
    )

    let completedEpisodes =
      try await observatory.podcastEpisodes(
        filter: Episode.completed,
        order: Episode.Columns.completionDate.desc
      )
      .get()
    #expect(completedEpisodes.count == 3)
    #expect(completedEpisodes.map(\.episode.guid) == ["top", "middle", "bottom"])
  }

  @Test("podcastSeries(FeedURL)")
  func testPodcastSeries() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    try await repo.insertSeries(unsavedPodcast)

    let series = try await observatory.podcastSeries(unsavedPodcast.feedURL).get()
    #expect(series?.podcast.feedURL == unsavedPodcast.feedURL)
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

  @Test("podcastEpisodesByMediaURLs() with empty array")
  func testPodcastEpisodesByMediaURLsEmpty() async throws {
    // Test with empty array
    let episodes = try await observatory.podcastEpisodesByMediaURLs([]).get()
    #expect(episodes.isEmpty)
  }

  @Test("podcastEpisodesByMediaURLs() with non-existing episodes")
  func testPodcastEpisodesByMediaURLsNonExisting() async throws {
    // Test with media URLs that don't exist in database
    let nonExistentMediaURLs = [
      MediaURL(URL.valid()),
      MediaURL(URL.valid()),
      MediaURL(URL.valid()),
    ]

    let episodes = try await observatory.podcastEpisodesByMediaURLs(nonExistentMediaURLs).get()
    #expect(episodes.isEmpty)
  }

  @Test("podcastEpisodesByMediaURLs() with existing episodes")
  func testPodcastEpisodesByMediaURLsExisting() async throws {
    // Create test episodes with specific media URLs
    let mediaURL1 = MediaURL(URL.valid())
    let mediaURL2 = MediaURL(URL.valid())
    let mediaURL3 = MediaURL(URL.valid())

    let unsavedPodcast = try Create.unsavedPodcast()
    try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [
        Create.unsavedEpisode(guid: "episode1", media: mediaURL1, title: "Episode 1"),
        Create.unsavedEpisode(guid: "episode2", media: mediaURL2, title: "Episode 2"),
        Create.unsavedEpisode(guid: "episode3", media: mediaURL3, title: "Episode 3"),
        Create.unsavedEpisode(guid: "episode4", title: "Episode 4"),  // Different media URL
      ]
    )

    // Test querying for specific episodes
    let episodes =
      try await observatory.podcastEpisodesByMediaURLs(
        [mediaURL1, mediaURL2]
      )
      .get()

    #expect(episodes.count == 2)
    let episodeTitles = Set(episodes.map(\.episode.title))
    #expect(episodeTitles == Set(["Episode 1", "Episode 2"]))

    // Verify the media URLs match
    let returnedMediaURLs = Set(episodes.map(\.episode.media))
    #expect(returnedMediaURLs == Set([mediaURL1, mediaURL2]))
  }

  @Test("podcastEpisodesByMediaURLs() with mixed existing and non-existing")
  func testPodcastEpisodesByMediaURLsMixed() async throws {
    // Create test episodes
    let existingMediaURL1 = MediaURL(URL.valid())
    let existingMediaURL2 = MediaURL(URL.valid())
    let nonExistentMediaURL = MediaURL(URL.valid())

    let unsavedPodcast = try Create.unsavedPodcast()
    try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [
        Create.unsavedEpisode(guid: "existing1", media: existingMediaURL1, title: "Existing 1"),
        Create.unsavedEpisode(guid: "existing2", media: existingMediaURL2, title: "Existing 2"),
      ]
    )

    // Query with mix of existing and non-existing media URLs
    let episodes =
      try await observatory.podcastEpisodesByMediaURLs(
        [existingMediaURL1, nonExistentMediaURL, existingMediaURL2]
      )
      .get()

    #expect(episodes.count == 2)
    let episodeTitles = Set(episodes.map(\.episode.title))
    #expect(episodeTitles == Set(["Existing 1", "Existing 2"]))
  }

  @Test("podcastEpisodesByMediaURLs() with custom order and limit")
  func testPodcastEpisodesByMediaURLsOrderAndLimit() async throws {
    // Create episodes with different pub dates
    let mediaURL1 = MediaURL(URL.valid())
    let mediaURL2 = MediaURL(URL.valid())
    let mediaURL3 = MediaURL(URL.valid())

    let unsavedPodcast = try Create.unsavedPodcast()
    try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [
        Create.unsavedEpisode(
          guid: "newest",
          media: mediaURL1,
          title: "Newest Episode",
          pubDate: 1.minutesAgo
        ),
        Create.unsavedEpisode(
          guid: "oldest",
          media: mediaURL2,
          title: "Oldest Episode",
          pubDate: 60.minutesAgo
        ),
        Create.unsavedEpisode(
          guid: "middle",
          media: mediaURL3,
          title: "Middle Episode",
          pubDate: 30.minutesAgo
        ),
      ]
    )

    // Test ascending order
    let episodesAsc =
      try await observatory.podcastEpisodesByMediaURLs(
        [mediaURL1, mediaURL2, mediaURL3],
        order: Episode.Columns.pubDate.asc
      )
      .get()

    #expect(episodesAsc.count == 3)
    #expect(
      episodesAsc.map(\.episode.title) == ["Oldest Episode", "Middle Episode", "Newest Episode"]
    )

    // Test with limit
    let episodesLimited =
      try await observatory.podcastEpisodesByMediaURLs(
        [mediaURL1, mediaURL2, mediaURL3],
        order: Episode.Columns.pubDate.desc,
        limit: 2
      )
      .get()

    #expect(episodesLimited.count == 2)
    #expect(episodesLimited.map(\.episode.title) == ["Newest Episode", "Middle Episode"])
  }

  @Test("podcastEpisodesByMediaURLs() AsyncSequence receives updates")
  func testPodcastEpisodesByMediaURLsAsyncSequence() async throws {
    let mediaURL1 = MediaURL(URL.valid())
    let mediaURL2 = MediaURL(URL.valid())

    let observedEpisodes = ActorContainer<[PodcastEpisode]>()

    // Start observing before any episodes exist
    Task {
      for try await episodes in observatory.podcastEpisodesByMediaURLs([mediaURL1, mediaURL2]) {
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
          guid: "episode1",
          media: mediaURL1,
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
          guid: "episode2",
          media: mediaURL2,
          title: "Episode 2",
          pubDate: 10.minutesAgo
        )
      ]
    )
    let episode2 = PodcastEpisode(podcast: series2.podcast, episode: series2.episodes[0])

    // Wait for observation with both episodes (ordered by pubDate desc by default)
    // Episode 1 should come first since it's newer
    try await observedEpisodes.waitForEqual(to: [episode1, episode2])

    // Step 4: Insert episode with different media URL (should not trigger update)
    let unsavedPodcast3 = try Create.unsavedPodcast()
    try await repo.insertSeries(
      unsavedPodcast3,
      unsavedEpisodes: [Create.unsavedEpisode(title: "Episode 3 - Different Media")]
    )

    // Should still have only 2 podcastEpisodes (no new update for unrelated episode)
    try await observedEpisodes.waitForEqual(to: [episode1, episode2])
  }
}
