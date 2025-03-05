// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of Episode model tests")
actor EpisodeTests {
  private let repo: Repo = .inMemory()

  @Test("that episodes are created and fetched in the right order")
  func createSeveralEpisodes() async throws {
    let url = URL.valid()
    let unsavedPodcast = try TestHelpers.unsavedPodcast(feedURL: FeedURL(url))

    let newestUnsavedEpisode = try TestHelpers.unsavedEpisode()
    let oldUnsavedEpisode = try TestHelpers.unsavedEpisode(
      pubDate: Calendar.current.date(byAdding: .day, value: -10, to: Date())
    )
    let middleUnsavedEpisode = try TestHelpers.unsavedEpisode(
      pubDate: Calendar.current.date(byAdding: .day, value: -5, to: Date())
    )
    let ancientUnsavedEpisode = try TestHelpers.unsavedEpisode(
      pubDate: Calendar.current.date(byAdding: .day, value: -1000, to: Date())
    )

    try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [
        middleUnsavedEpisode,
        ancientUnsavedEpisode,
        oldUnsavedEpisode,
        newestUnsavedEpisode,
      ]
    )

    let podcastSeries = try await repo.db.read { db in
      try Podcast
        .filter(Schema.feedURLColumn == url)
        .including(all: Podcast.episodes)
        .asRequest(of: PodcastSeries.self)
        .fetchOne(db)
    }!
    #expect(
      podcastSeries.episodes.elements
        == podcastSeries.episodes.sorted { $0.pubDate > $1.pubDate }
    )
  }

  @Test("that a series with new episodes can be refreshed")
  func refreshSeriesWithNewEpisodes() async throws {
    let unsavedPodcast = try TestHelpers.unsavedPodcast(title: "original podcast title")
    let oldEpisode = try TestHelpers.unsavedEpisode(title: "original")
    let podcastSeries = try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [oldEpisode]
    )
    #expect(podcastSeries.episodes.count == 1)
    var podcast = podcastSeries.podcast
    #expect(podcast.title == "original podcast title")
    podcast.title = "new podcast title"
    var episode = podcastSeries.episodes.first!
    #expect(episode.title == "original")
    episode.title = "new title"
    let newEpisode = try TestHelpers.unsavedEpisode(title: "episode 2")
    try await repo.updateSeries(
      podcast,
      unsavedEpisodes: [newEpisode],
      existingEpisodes: [episode]
    )

    let fetchedSeries = try await repo.podcastSeries(podcastSeries.podcast.id)!
    #expect(fetchedSeries.podcast.title == "new podcast title")
    #expect(fetchedSeries.episodes.count == 2)
    #expect(fetchedSeries.episodes.last!.title == "new title")
    #expect(fetchedSeries.episodes.first!.title == "episode 2")
  }

  @Test("that episodes can persist currentTime")
  func persistCurrentTime() async throws {
    let guid = GUID("guid")
    let cmTime = CMTime.inSeconds(30)

    let unsavedPodcast = try TestHelpers.unsavedPodcast()
    let unsavedEpisode = try TestHelpers.unsavedEpisode(guid: guid, currentTime: cmTime)
    let podcastSeries = try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [unsavedEpisode]
    )
    let podcast = podcastSeries.podcast

    let episode = try await repo.db.read { db in
      try Episode.fetchOne(db, key: ["guid": guid, "podcastId": podcast.id])
    }!
    #expect(episode.currentTime == cmTime)

    let newCMTime = CMTime.inSeconds(60)
    try await repo.updateCurrentTime(episode.id, newCMTime)

    let updatedEpisode = try await repo.db.read { db in
      try Episode.fetchOne(db, id: episode.id)
    }!
    #expect(updatedEpisode.currentTime == newCMTime)
  }

  @Test("that an episode can be fetched by its media url")
  func fetchEpisodeByMediaURL() async throws {
    let unsavedPodcast = try TestHelpers.unsavedPodcast()
    let unsavedEpisode = try TestHelpers.unsavedEpisode()
    try await repo.insertSeries(unsavedPodcast, unsavedEpisodes: [unsavedEpisode])

    let podcastEpisode = try await repo.episode(unsavedEpisode.media)!
    #expect(podcastEpisode.episode.media == unsavedEpisode.media)
  }

  @Test("that multiple episodes can be fetched by their media url")
  func fetchEpisodesByMediaURLs() async throws {
    let unsavedPodcast = try TestHelpers.unsavedPodcast()
    let unsavedEpisode1 = try TestHelpers.unsavedEpisode()
    let unsavedEpisode2 = try TestHelpers.unsavedEpisode()
    try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [unsavedEpisode1, unsavedEpisode2]
    )

    let unsavedPodcast2 = try TestHelpers.unsavedPodcast()
    let unsavedEpisode21 = try TestHelpers.unsavedEpisode()
    let unsavedEpisode22 = try TestHelpers.unsavedEpisode()
    try await repo.insertSeries(
      unsavedPodcast2,
      unsavedEpisodes: [unsavedEpisode21, unsavedEpisode22]
    )

    let unsavedEpisodeNeverSaved = try TestHelpers.unsavedEpisode()

    let podcastEpisodes = try await repo.episodes([
      unsavedEpisode1.media, unsavedEpisode2.media, unsavedEpisode21.media, unsavedEpisode22.media,
      unsavedEpisodeNeverSaved.media,
    ])
    #expect(podcastEpisodes.count == 4)
    #expect(
      Set(podcastEpisodes.map(\.episode.media))
        == Set(
          [
            unsavedEpisode1.media,
            unsavedEpisode2.media,
            unsavedEpisode21.media,
            unsavedEpisode22.media,
          ]
        )
    )
    #expect(
      Set(podcastEpisodes.map(\.podcast.feedURL))
        == Set([unsavedPodcast.feedURL, unsavedPodcast2.feedURL])
    )
  }

  @Test("that an episode can be marked complete")
  func markEpisodeComplete() async throws {
    let unsavedPodcast = try TestHelpers.unsavedPodcast()
    let unsavedEpisode = try TestHelpers.unsavedEpisode(currentTime: CMTime.inSeconds(60))
    let podcastSeries = try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [unsavedEpisode]
    )

    let episode = podcastSeries.episodes.first!
    #expect(episode.completed == false)
    #expect(episode.currentTime == CMTime.inSeconds(60))
    try await repo.markComplete(episode.id)

    let podcastEpisode = try await repo.episode(episode.id)!
    #expect(podcastEpisode.episode.completed == true)
    #expect(podcastEpisode.episode.currentTime == CMTime.zero)
  }

  @Test("that fetchOrInsertEpisodes works when things exist or are new")
  func testFetchOrInsertEpisodes() async throws {
    let insertedPodcast = try TestHelpers.unsavedPodcast()
    let unsavedEpisodeInsertedPodcast = try TestHelpers.unsavedEpisode()
    try await repo.insertSeries(insertedPodcast)

    let unsavedPodcast = try TestHelpers.unsavedPodcast()
    let unsavedEpisode = try TestHelpers.unsavedEpisode()

    let podcastEpisodes = try await repo.fetchOrInsertEpisodes([
      UnsavedPodcastEpisode(
        unsavedPodcast: insertedPodcast,
        unsavedEpisode: unsavedEpisodeInsertedPodcast
      ),
      UnsavedPodcastEpisode(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisode: unsavedEpisode
      ),
    ])
    #expect(podcastEpisodes.count == 2)
    #expect(
      Set(podcastEpisodes.map(\.podcast.feedURL))
        == Set([insertedPodcast.feedURL, unsavedPodcast.feedURL])
    )
    #expect(
      Set(podcastEpisodes.map(\.episode.media))
        == Set([unsavedEpisodeInsertedPodcast.media, unsavedEpisode.media])
    )

    let firstPodcastEpisode = try await repo.episode(podcastEpisodes[0].id)!
    let secondPodcastEpisode = try await repo.episode(podcastEpisodes[1].id)!
    #expect(
      Set(podcastEpisodes.map(\.podcast.id))
        == Set([firstPodcastEpisode.podcast.id, secondPodcastEpisode.podcast.id])
    )
    #expect(
      Set(podcastEpisodes.map(\.episode.id))
        == Set([firstPodcastEpisode.episode.id, secondPodcastEpisode.episode.id])
    )
  }
}
