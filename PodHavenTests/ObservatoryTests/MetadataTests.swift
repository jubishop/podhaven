// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import IdentifiedCollections
import Testing

@testable import PodHaven

@Suite("of Observatory metadata tests", .container)
actor MetadataTests {
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.repo) private var repo

  @Test("podcastsWithEpisodeMetadata() with zero episodes")
  func testPodcastsWithEpisodeMetadataZeroEpisodes() async throws {
    let podcastWithNoEpisodes = try Create.unsavedPodcast()
    try await repo.insertSeries(UnsavedPodcastSeries(unsavedPodcast: podcastWithNoEpisodes))

    let allPodcastsWithEpisodeMetadata =
      try await observatory.podcastsWithEpisodeMetadata().get()

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
        uniqueElements: try await observatory.podcastsWithEpisodeMetadata().get(),
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
}
