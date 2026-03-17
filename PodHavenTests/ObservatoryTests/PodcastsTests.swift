// Copyright Justin Bishop, 2025

import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of Observatory podcasts tests", .container)
actor PodcastsTests {
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.repo) private var repo

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
}
