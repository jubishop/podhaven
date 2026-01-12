// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("Episode refresh tests", .container)
class EpisodeRefreshTests {
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.repo) private var repo

  @Test("that a series with new episodes can be refreshed")
  func refreshSeriesWithNewEpisodes() async throws {
    // Step 1: Insert podcast and episodes into repo
    let unsavedPodcast = try Create.unsavedPodcast(
      feedURL: FeedURL(URL.valid()),
      title: "original podcast title",
      image: URL.valid(),
      description: "original podcast description",
      link: URL.valid(),
      subscriptionDate: nil
    )
    let unsavedEpisode = try Create.unsavedEpisode(
      mediaURL: MediaURL(URL.valid()),
      title: "original episode title",
      pubDate: 100.minutesAgo,
      duration: CMTime.seconds(300),
      description: "original episode description",
      link: URL.valid(),
      image: URL.valid()
    )
    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: [unsavedEpisode]
      )
    )

    let originalPodcast = podcastSeries.podcast
    let originalEpisode = podcastSeries.episodes.first!

    // Step 2: Update user state and duration (simulating PodAVPlayer updating duration)
    let actualDuration = CMTime.seconds(1800)  // 30 minutes actual duration from media file
    let currentTime = CMTime.seconds(120)
    try await repo.markSubscribed(originalPodcast.id)
    try await repo.markFinished(originalEpisode.id)
    try await repo.updateCurrentTime(originalEpisode.id, currentTime: currentTime)
    try await repo.updateDuration(originalEpisode.id, duration: actualDuration)
    try await queue.unshift(originalEpisode.id)

    // Step 3: Call updateSeries with RSS feed data (simulating what would come from a feed refresh)
    let newFeedURL = FeedURL(URL.valid())
    let newPodcastTitle = "new podcast title"
    let newPodcastImage = URL.valid()
    let newPodcastDescription = "new podcast description"
    let newPodcastLink = URL.valid()
    let newLastUpdate = 10.minutesAgo

    let updatedPodcast = try Podcast(
      id: originalPodcast.id,
      creationDate: originalPodcast.creationDate,
      from: Create.unsavedPodcast(
        feedURL: newFeedURL,
        title: newPodcastTitle,
        image: newPodcastImage,
        description: newPodcastDescription,
        link: newPodcastLink,
        lastUpdate: newLastUpdate
      )
    )

    let newEpisodeGUID: GUID = GUID(String.random())
    let newEpisodeMedia = MediaURL(URL.valid())
    let newEpisodeTitle = "new episode title"
    let newEpisodePubDate = 50.minutesAgo
    let newEpisodeDuration = CMTime.seconds(600)
    let newEpisodeDescription = "new episode description"
    let newEpisodeLink = URL.valid()
    let newEpisodeImage = URL.valid()

    let updatedEpisode = try Episode(
      id: originalEpisode.id,
      creationDate: originalEpisode.creationDate,
      from: Create.unsavedEpisode(
        guid: newEpisodeGUID,
        mediaURL: newEpisodeMedia,
        title: newEpisodeTitle,
        pubDate: newEpisodePubDate,
        duration: newEpisodeDuration,
        description: newEpisodeDescription,
        link: newEpisodeLink,
        image: newEpisodeImage
      )
    )

    let newUnsavedEpisode = try Create.unsavedEpisode(title: "episode 2")
    let newEpisodes = try await repo.updateSeriesFromFeed(
      podcastSeries: PodcastSeries(podcast: updatedPodcast),
      podcast: updatedPodcast,
      unsavedEpisodes: [newUnsavedEpisode],
      existingEpisodes: [updatedEpisode]
    )
    #expect(newEpisodes.map(\.mediaGUID) == [newUnsavedEpisode.mediaGUID])

    // Step 4: Confirm user state from step 2 wasn't overwritten by step 3
    let updatedSeries = try await repo.podcastSeries(originalPodcast.id)!
    let updatedExistingEpisode = updatedSeries.episodes.first { $0.title == newEpisodeTitle }!

    // Verify we're testing all Podcast RSS columns (test will fail if rssUpdatableColumns changes)
    let podcastRSSColumnNames = Set(updatedPodcast.rssUpdatableColumns.map { $0.0.name })
    let expectedPodcastColumns = Set([
      "feedURL", "title", "image", "description", "link",
    ])
    #expect(
      podcastRSSColumnNames == expectedPodcastColumns,
      "Test must be updated if Podcast.rssUpdatableColumns changes"
    )

    // All RSS attributes should be updated for podcast
    #expect(updatedSeries.podcast.feedURL == newFeedURL)
    #expect(updatedSeries.podcast.title == newPodcastTitle)
    #expect(updatedSeries.podcast.image == newPodcastImage)
    #expect(updatedSeries.podcast.description == newPodcastDescription)
    #expect(updatedSeries.podcast.link == newPodcastLink)

    // Verify we're testing all Episode RSS columns (test will fail if rssUpdatableColumns changes)
    let episodeRSSColumnNames = Set(updatedEpisode.rssUpdatableColumns.map { $0.0.name })
    let expectedEpisodeColumns = Set([
      "guid", "mediaURL", "title", "pubDate", "description", "link", "image",
    ])
    #expect(
      episodeRSSColumnNames == expectedEpisodeColumns,
      "Test must be updated if Episode.rssUpdatableColumns changes"
    )

    // RSS attributes should be updated for existing episode (excluding duration)
    #expect(updatedExistingEpisode.guid == newEpisodeGUID)
    #expect(updatedExistingEpisode.mediaURL == newEpisodeMedia)
    #expect(updatedExistingEpisode.title == newEpisodeTitle)
    #expect(updatedExistingEpisode.pubDate.approximatelyEquals(newEpisodePubDate))
    #expect(updatedExistingEpisode.description == newEpisodeDescription)
    #expect(updatedExistingEpisode.link == newEpisodeLink)
    #expect(updatedExistingEpisode.image == newEpisodeImage)

    // Non-RSS attributes should be preserved (not overwritten by original values)
    #expect(updatedSeries.podcast.subscribed == true)
    #expect(updatedExistingEpisode.currentTime == currentTime)
    #expect(updatedExistingEpisode.finishDate != nil)
    #expect(updatedExistingEpisode.queueOrder == 0)
    #expect(updatedExistingEpisode.duration == actualDuration)
  }
}
