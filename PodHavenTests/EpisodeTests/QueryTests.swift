// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of Episode query tests", .container)
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

  @Test("podcastEpisodes(_:) returns rows in input order")
  func podcastEpisodesPreservesInputOrder() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: "ep-a"),
          try Create.unsavedEpisode(guid: "ep-b"),
          try Create.unsavedEpisode(guid: "ep-c"),
          try Create.unsavedEpisode(guid: "ep-d"),
        ]
      )
    )
    let ids = series.episodes.map(\.id)
    let reversed = Array(ids.reversed())
    let scrambled = [ids[2], ids[0], ids[3], ids[1]]

    let inserted = try await repo.podcastEpisodes(ids)
    #expect(inserted.map(\.id) == ids)

    let reversedFetch = try await repo.podcastEpisodes(reversed)
    #expect(reversedFetch.map(\.id) == reversed)

    let scrambledFetch = try await repo.podcastEpisodes(scrambled)
    #expect(scrambledFetch.map(\.id) == scrambled)
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

    // Query by (MediaGUID, feedURL) should match query by ID
    let podcastEpisodeByGUID = try await repo.podcastEpisode(
      mediaGUID,
      feedURL: podcastSeries.podcast.feedURL
    )
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

    let podcastEpisode = try await repo.podcastEpisode(
      nonExistentMediaGUID,
      feedURL: FeedURL(URL.valid())
    )
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

    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: [unsavedEpisode1, unsavedEpisode2]
      )
    )
    let feedURL = podcastSeries.podcast.feedURL

    // Each MediaGUID resolves to the correct episode within its podcast
    let found1 = try await repo.podcastEpisode(episode1MediaGUID, feedURL: feedURL)
    let found2 = try await repo.podcastEpisode(episode2MediaGUID, feedURL: feedURL)

    #expect(found1 != nil)
    #expect(found2 != nil)
    #expect(found1?.episode.title == "Episode 1")
    #expect(found2?.episode.title == "Episode 2")
    #expect(found1?.episode.guid == episode1GUID)
    #expect(found2?.episode.guid == episode2GUID)
    #expect(found1?.episode.mediaURL == episode1Media)
    #expect(found2?.episode.mediaURL == episode2Media)
  }

  @Test("update and fetch episode downloading flag")
  func updateAndFetchDownloading() async throws {
    let (one, _) = try await Create.twoPodcastEpisodes()

    #expect(try await repo.episode(one.id)?.downloading == false)

    let setTrue = try await repo.updateDownloading(one.id, downloading: true)
    #expect(setTrue)
    #expect(try await repo.episode(one.id)?.downloading == true)

    let setFalse = try await repo.updateDownloading(one.id, downloading: false)
    #expect(setFalse)
    #expect(try await repo.episode(one.id)?.downloading == false)
  }

  // MARK: - Batch podcastEpisodes

  @Test("podcastEpisodes([]) returns empty array")
  func podcastEpisodesBatchEmpty() async throws {
    let results = try await repo.podcastEpisodes([])
    #expect(results.isEmpty)
  }

  @Test("podcastEpisodes returns all requested episodes with their podcasts")
  func podcastEpisodesBatchReturnsAll() async throws {
    let unsavedPodcast = try Create.unsavedPodcast(title: "Batch Podcast")
    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: "batch-1", title: "Episode 1"),
          try Create.unsavedEpisode(guid: "batch-2", title: "Episode 2"),
          try Create.unsavedEpisode(guid: "batch-3", title: "Episode 3"),
        ]
      )
    )

    let allIDs = podcastSeries.episodes.map(\.id)
    let results = try await repo.podcastEpisodes(allIDs)

    #expect(results.count == 3)
    #expect(Set(results.map(\.id)) == Set(allIDs))
    for result in results {
      #expect(result.podcast.title == "Batch Podcast")
    }
  }

  @Test("podcastEpisodes skips non-existent IDs without error")
  func podcastEpisodesBatchSkipsNonExistent() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let nonExistentID = Episode.ID(rawValue: 999_999)

    let results = try await repo.podcastEpisodes([podcastEpisode.id, nonExistentID])

    #expect(results.count == 1)
    #expect(results[0].id == podcastEpisode.id)
  }

  @Test("podcastEpisodes returns episodes from multiple podcasts")
  func podcastEpisodesBatchAcrossPodcasts() async throws {
    let series1 = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(title: "Podcast A"),
        unsavedEpisodes: [try Create.unsavedEpisode(guid: "a-1", title: "A Episode")]
      )
    )
    let series2 = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(title: "Podcast B"),
        unsavedEpisodes: [try Create.unsavedEpisode(guid: "b-1", title: "B Episode")]
      )
    )

    let results = try await repo.podcastEpisodes([
      series1.episodes[0].id,
      series2.episodes[0].id,
    ])

    #expect(results.count == 2)
    let titles = Set(results.map(\.podcast.title))
    #expect(titles == Set(["Podcast A", "Podcast B"]))
  }
}
