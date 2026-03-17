// Copyright Justin Bishop, 2025

import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of Observatory podcastEpisodes tests", .container)
actor PodcastEpisodesTests {
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.repo) private var repo

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
}
