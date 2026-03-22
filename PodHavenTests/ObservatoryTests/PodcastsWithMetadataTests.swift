// Copyright Justin Bishop, 2025

import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of Observatory podcastsWithEpisodeMetadata(feedURLs) tests", .container)
actor PodcastsWithMetadataTests {
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.repo) private var repo

  @Test("podcastsWithEpisodeMetadata(feedURLs) with empty array")
  func testPodcastsWithEpisodeMetadataFeedURLsEmpty() async throws {
    // Test with empty array
    let podcastsWithMetadata: [PodcastWithEpisodeMetadata<Podcast>] =
      try await observatory.podcastsWithEpisodeMetadata([]).get()
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

    let podcastsWithMetadata: [PodcastWithEpisodeMetadata<Podcast>] =
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
    let podcastsWithMetadata: [PodcastWithEpisodeMetadata<Podcast>] =
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
    let podcastsWithMetadata: [PodcastWithEpisodeMetadata<Podcast>] =
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
    let podcastsWithMetadataLimited: [PodcastWithEpisodeMetadata<Podcast>] =
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
      let observation: AsyncValueObservation<[PodcastWithEpisodeMetadata<Podcast>]> =
        observatory.podcastsWithEpisodeMetadata([feedURL1, feedURL2])

      for try await metadata in observation {
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
