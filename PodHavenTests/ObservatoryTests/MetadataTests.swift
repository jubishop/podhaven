// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import GRDB
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

    let allPodcastsWithEpisodeMetadata: [PodcastWithEpisodeMetadata<Podcast>] =
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

    let allPodcastsWithEpisodeMetadata: [PodcastWithEpisodeMetadata<Podcast>] =
      try await observatory.podcastsWithEpisodeMetadata().get()
    #expect(allPodcastsWithEpisodeMetadata.count == 2)

    let podcastWithMetadata = allPodcastsWithEpisodeMetadata.first {
      $0.feedURL == podcast.feedURL
    }!
    #expect(podcastWithMetadata.episodeCount == 5)
    #expect(
      podcastWithMetadata.mostRecentEpisodeDate!
        .approximatelyEquals(newerPlayedEpisode.pubDate)
    )

    let fetchedPodcastAllPlayed = allPodcastsWithEpisodeMetadata.first {
      $0.feedURL == podcastAllPlayed.feedURL
    }!
    #expect(fetchedPodcastAllPlayed.episodeCount == 1)
    #expect(
      fetchedPodcastAllPlayed.mostRecentEpisodeDate!
        .approximatelyEquals(playedEpisode.pubDate)
    )
  }

  // MARK: - Tags

  @Test("podcastsWithEpisodeMetadata() carries each podcast's tag IDs")
  func testPodcastsWithEpisodeMetadataCarriesTags() async throws {
    let taggedPodcast = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: try Create.unsavedPodcast(title: "Tagged"))
    )
    let untaggedPodcast = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: try Create.unsavedPodcast(title: "Untagged"))
    )

    let zebra = try await repo.insertTag(UnsavedTag(name: "zebra"))
    let apple = try await repo.insertTag(UnsavedTag(name: "Apple"))
    let mango = try await repo.insertTag(UnsavedTag(name: "mango"))

    try await repo.addTag(zebra.id, to: taggedPodcast.id)
    try await repo.addTag(apple.id, to: taggedPodcast.id)
    try await repo.addTag(mango.id, to: taggedPodcast.id)

    let results: [PodcastWithEpisodeMetadata<Podcast>] =
      try await observatory.podcastsWithEpisodeMetadata().get()

    let taggedResult = results.first { $0.feedURL == taggedPodcast.podcast.feedURL }!
    #expect(taggedResult.tagIDs == [apple.id, mango.id, zebra.id])

    let untaggedResult = results.first { $0.feedURL == untaggedPodcast.podcast.feedURL }!
    #expect(untaggedResult.tagIDs.isEmpty)
  }

  @Test("listablePodcastsWithEpisodeMetadata() also carries tag IDs")
  func testListablePodcastsWithEpisodeMetadataCarriesTags() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: try Create.unsavedPodcast())
    )
    let tag = try await repo.insertTag(UnsavedTag(name: "Swift"))
    try await repo.addTag(tag.id, to: series.id)

    let results: [PodcastWithEpisodeMetadata<ListablePodcast>] =
      try await observatory.listablePodcastsWithEpisodeMetadata().get()

    #expect(results.count == 1)
    #expect(results[0].tagIDs == [tag.id])
  }

  // MARK: - Freshness Cadence

  @Test("resolvedFreshnessCadence carries the cached inference from episodes")
  func testResolvedFreshnessCadenceFromInference() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: try [0, 7, 14, 21, 28]
          .map {
            try Create.unsavedEpisode(pubDate: $0.daysAgo)
          }
      )
    )

    let results: [PodcastWithEpisodeMetadata<ListablePodcast>] =
      try await observatory.listablePodcastsWithEpisodeMetadata().get()
    let result = results.first { $0.feedURL == series.podcast.feedURL }!
    #expect(result.resolvedFreshnessCadence == .weekly)
  }

  @Test("resolvedFreshnessCadence prefers the manual override over the inference")
  func testResolvedFreshnessCadencePrefersManualOverride() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: try [0, 7, 14, 21, 28]
          .map {
            try Create.unsavedEpisode(pubDate: $0.daysAgo)
          }
      )
    )
    var settings = PodcastSettings.defaults
    settings.freshnessCadence = .daily
    _ = try await repo.updatePodcastSettings(series.podcast.id, settings)

    let results: [PodcastWithEpisodeMetadata<ListablePodcast>] =
      try await observatory.listablePodcastsWithEpisodeMetadata().get()
    let result = results.first { $0.feedURL == series.podcast.feedURL }!
    #expect(result.resolvedFreshnessCadence == .daily)
  }

  @Test("resolvedFreshnessCadence is nil for a podcast with no episodes")
  func testResolvedFreshnessCadenceNilWithoutEpisodes() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: try Create.unsavedPodcast())
    )

    let results: [PodcastWithEpisodeMetadata<ListablePodcast>] =
      try await observatory.listablePodcastsWithEpisodeMetadata().get()
    let result = results.first { $0.feedURL == series.podcast.feedURL }!
    #expect(result.resolvedFreshnessCadence == nil)
  }
}
