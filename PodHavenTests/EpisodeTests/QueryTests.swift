// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("Episode query tests", .container)
class EpisodeQueryTests {
  @DynamicInjected(\.repo) private var repo

  @Test("that latestEpisode returns the most recent episode for a podcast")
  func latestEpisode() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()

    let oldestEpisode = try Create.unsavedEpisode(pubDate: 100.minutesAgo)
    let middleEpisode = try Create.unsavedEpisode(pubDate: 50.minutesAgo)
    let newestEpisode = try Create.unsavedEpisode(pubDate: 10.minutesAgo)

    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: [oldestEpisode, newestEpisode, middleEpisode]
      )
    )

    let latestEpisode = try await repo.latestEpisode(for: podcastSeries.podcast.id)

    #expect(latestEpisode != nil)
    #expect(latestEpisode?.guid == newestEpisode.guid)
    #expect(latestEpisode?.pubDate.approximatelyEquals(newestEpisode.pubDate) == true)
  }

  @Test("that latestEpisode returns nil when podcast has no episodes")
  func latestEpisodeNoPodcast() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: unsavedPodcast, unsavedEpisodes: [])
    )
    let latestEpisode = try await repo.latestEpisode(for: podcastSeries.id)

    #expect(latestEpisode == nil)
  }

  @Test("that episode can be queried by MediaGUID")
  func testEpisodeQueryByMediaGUID() async throws {
    let guid = GUID("test-guid")
    let mediaURL = MediaURL(URL.valid())
    let mediaGUID = MediaGUID(guid: guid, mediaURL: mediaURL)

    let unsavedPodcast = try Create.unsavedPodcast()
    let unsavedEpisode = try Create.unsavedEpisode(
      guid: guid,
      mediaURL: mediaURL,
      title: "Episode with MediaGUID"
    )

    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: [unsavedEpisode]
      )
    )

    let insertedEpisode = podcastSeries.episodes.first!

    // Query by MediaGUID should return the same episode as query by ID
    let episodeByGUID = try await repo.episode(mediaGUID)
    let episodeByID = try await repo.episode(insertedEpisode.id)

    #expect(episodeByGUID != nil)
    #expect(episodeByID != nil)
    #expect(episodeByGUID?.id == episodeByID?.id)
    #expect(episodeByGUID?.guid == guid)
    #expect(episodeByGUID?.mediaURL == mediaURL)
    #expect(episodeByGUID?.title == "Episode with MediaGUID")
  }

  @Test("that episode query by MediaGUID returns nil for non-existent episode")
  func testEpisodeQueryByMediaGUIDNonExistent() async throws {
    let nonExistentMediaGUID = MediaGUID(
      guid: GUID("non-existent-guid"),
      mediaURL: MediaURL(URL.valid())
    )

    let episode = try await repo.episode(nonExistentMediaGUID)
    #expect(episode == nil)
  }

  @Test("that podcastEpisode can be queried by MediaGUID")
  func testPodcastEpisodeQueryByMediaGUID() async throws {
    let guid = GUID("test-podcast-episode-guid")
    let mediaURL = MediaURL(URL.valid())
    let mediaGUID = MediaGUID(guid: guid, mediaURL: mediaURL)

    let unsavedPodcast = try Create.unsavedPodcast(title: "Test Podcast")
    let unsavedEpisode = try Create.unsavedEpisode(
      guid: guid,
      mediaURL: mediaURL,
      title: "Test Episode"
    )

    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: [unsavedEpisode]
      )
    )

    let insertedEpisode = podcastSeries.episodes.first!

    // Query by MediaGUID should return the same podcastEpisode as query by ID
    let podcastEpisodeByGUID = try await repo.podcastEpisode(mediaGUID)
    let podcastEpisodeByID = try await repo.podcastEpisode(insertedEpisode.id)

    #expect(podcastEpisodeByGUID != nil)
    #expect(podcastEpisodeByID != nil)
    #expect(podcastEpisodeByGUID?.id == podcastEpisodeByID?.id)
    #expect(podcastEpisodeByGUID?.episode.guid == guid)
    #expect(podcastEpisodeByGUID?.episode.mediaURL == mediaURL)
    #expect(podcastEpisodeByGUID?.episode.title == "Test Episode")
    #expect(podcastEpisodeByGUID?.podcast.title == "Test Podcast")
  }

  @Test("that podcastEpisode query by MediaGUID returns nil for non-existent episode")
  func testPodcastEpisodeQueryByMediaGUIDNonExistent() async throws {
    let nonExistentMediaGUID = MediaGUID(
      guid: GUID("non-existent-podcast-episode-guid"),
      mediaURL: MediaURL(URL.valid())
    )

    let podcastEpisode = try await repo.podcastEpisode(nonExistentMediaGUID)
    #expect(podcastEpisode == nil)
  }

  @Test("that MediaGUID queries are consistent across multiple episodes")
  func testMediaGUIDQueriesConsistency() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()

    let episode1GUID = GUID("episode-1")
    let episode1Media = MediaURL(URL.valid())
    let episode1MediaGUID = MediaGUID(guid: episode1GUID, mediaURL: episode1Media)

    let episode2GUID = GUID("episode-2")
    let episode2Media = MediaURL(URL.valid())
    let episode2MediaGUID = MediaGUID(guid: episode2GUID, mediaURL: episode2Media)

    let unsavedEpisode1 = try Create.unsavedEpisode(
      guid: episode1GUID,
      mediaURL: episode1Media,
      title: "Episode 1"
    )
    let unsavedEpisode2 = try Create.unsavedEpisode(
      guid: episode2GUID,
      mediaURL: episode2Media,
      title: "Episode 2"
    )

    try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: [unsavedEpisode1, unsavedEpisode2]
      )
    )

    // Test that each MediaGUID returns the correct episode
    let foundEpisode1 = try await repo.episode(episode1MediaGUID)
    let foundEpisode2 = try await repo.episode(episode2MediaGUID)

    #expect(foundEpisode1 != nil)
    #expect(foundEpisode2 != nil)
    #expect(foundEpisode1?.title == "Episode 1")
    #expect(foundEpisode2?.title == "Episode 2")
    #expect(foundEpisode1?.guid == episode1GUID)
    #expect(foundEpisode2?.guid == episode2GUID)
    #expect(foundEpisode1?.mediaURL == episode1Media)
    #expect(foundEpisode2?.mediaURL == episode2Media)

    // Test with podcastEpisode queries as well
    let foundPodcastEpisode1 = try await repo.podcastEpisode(episode1MediaGUID)
    let foundPodcastEpisode2 = try await repo.podcastEpisode(episode2MediaGUID)

    #expect(foundPodcastEpisode1 != nil)
    #expect(foundPodcastEpisode2 != nil)
    #expect(foundPodcastEpisode1?.episode.title == "Episode 1")
    #expect(foundPodcastEpisode2?.episode.title == "Episode 2")
  }

  @Test("update and fetch episode by downloadTaskID")
  func updateAndFetchByTaskID() async throws {
    // Create two episodes
    let (one, two) = try await Create.twoPodcastEpisodes()

    let id1 = URLSessionDownloadTask.ID(101)
    let id2 = URLSessionDownloadTask.ID(202)

    // Set mapping for first
    let updated1 = try await repo.updateDownloadTaskID(one.id, downloadTaskID: id1)
    #expect(updated1)

    // Fetch by single task id
    let fetched1 = try await repo.episode(id1)
    #expect(fetched1 != nil)
    #expect(fetched1?.id == one.id)

    // Set mapping for second and verify batch fetch
    let updated2 = try await repo.updateDownloadTaskID(two.id, downloadTaskID: id2)
    #expect(updated2)

    let fetchedBatch = try await repo.episodes([id1, id2])
    #expect(fetchedBatch.count == 2)
    let fetchedIDs = Set(fetchedBatch.map(\.id))
    #expect(fetchedIDs == Set([one.id, two.id]))

    // Clear first mapping and verify lookup is nil
    _ = try await repo.updateDownloadTaskID(one.id, downloadTaskID: nil)
    let shouldBeNil = try await repo.episode(id1)
    #expect(shouldBeNil == nil)
  }

  @Test("unique constraint enforced when assigning duplicate downloadTaskID")
  func uniqueConstraintOnTaskID() async throws {
    let (one, two) = try await Create.twoPodcastEpisodes()
    let sharedID = URLSessionDownloadTask.ID(4242)

    _ = try await repo.updateDownloadTaskID(one.id, downloadTaskID: sharedID)

    await #expect(throws: DatabaseError.self) {
      _ = try await self.repo.updateDownloadTaskID(two.id, downloadTaskID: sharedID)
    }
  }

  @Test("episodes([]) returns empty array")
  func episodesEmptyBatch() async throws {
    let results = try await repo.episodes([])
    #expect(results.isEmpty)
  }
}
