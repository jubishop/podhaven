// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of Episode model tests", .container)
class EpisodeTests {
  @DynamicInjected(\.repo) private var repo

  @Test("that episodes are created and fetched in the right order")
  func createSeveralEpisodes() async throws {
    let url = URL.valid()
    let unsavedPodcast = try TestHelpers.unsavedPodcast(feedURL: FeedURL(url))

    let newestUnsavedEpisode = try TestHelpers.unsavedEpisode()
    let oldUnsavedEpisode = try TestHelpers.unsavedEpisode(pubDate: 10.minutesAgo)
    let middleUnsavedEpisode = try TestHelpers.unsavedEpisode(pubDate: 5.minutesAgo)
    let ancientUnsavedEpisode = try TestHelpers.unsavedEpisode(pubDate: 1000.minutesAgo)

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
        .filter { $0.feedURL == url }
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

  @Test("that episodes can persist duration")
  func persistDuration() async throws {
    let guid = GUID("guid")
    let cmTime = CMTime.inSeconds(30)

    let unsavedPodcast = try TestHelpers.unsavedPodcast()
    let unsavedEpisode = try TestHelpers.unsavedEpisode(guid: guid, duration: cmTime)
    let podcastSeries = try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [unsavedEpisode]
    )
    let podcast = podcastSeries.podcast

    let episode = try await repo.db.read { db in
      try Episode.fetchOne(db, key: ["guid": guid, "podcastId": podcast.id])
    }!
    #expect(episode.duration == cmTime)

    let newCMTime = CMTime.inSeconds(60)
    try await repo.updateDuration(episode.id, newCMTime)

    let updatedEpisode = try await repo.db.read { db in
      try Episode.fetchOne(db, id: episode.id)
    }!
    #expect(updatedEpisode.duration == newCMTime)
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

    let allPodcasts = [unsavedPodcast, unsavedPodcast2]
    let allEpisodes = [
      unsavedEpisode1, unsavedEpisode2, unsavedEpisode21, unsavedEpisode22,
    ]
    let unsavedEpisodeNeverSaved = try TestHelpers.unsavedEpisode()

    let podcastEpisodes = try await repo.episodes([
      unsavedEpisode1.media, unsavedEpisode2.media, unsavedEpisode21.media, unsavedEpisode22.media,
      unsavedEpisodeNeverSaved.media,
    ])
    #expect(podcastEpisodes.count == 4)
    #expect(Set(podcastEpisodes.map(\.episode.media)) == Set(allEpisodes.map(\.media)))
    #expect(Set(podcastEpisodes.map(\.podcast.feedURL)) == Set(allPodcasts.map(\.feedURL)))
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

  @Test("that upsertPodcastEpisode works when podcast exists or is new")
  func testAddEpisode() async throws {
    let unsavedPodcast = try TestHelpers.unsavedPodcast()
    let unsavedEpisode = try TestHelpers.unsavedEpisode()
    let insertedPodcastEpisode = try await repo.upsertPodcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisode: unsavedEpisode
      )
    )
    #expect(insertedPodcastEpisode.podcast.feedURL == unsavedPodcast.feedURL)
    #expect(insertedPodcastEpisode.episode.media == unsavedEpisode.media)

    let fetchedPodcastEpisode = try await repo.episode(insertedPodcastEpisode.id)!
    #expect(fetchedPodcastEpisode.podcast.title == insertedPodcastEpisode.podcast.title)
    #expect(fetchedPodcastEpisode.episode.guid == insertedPodcastEpisode.episode.guid)

    let secondUnsavedEpisode = try TestHelpers.unsavedEpisode()
    let _ = try await repo.upsertPodcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisode: secondUnsavedEpisode
      )
    )

    let fetchedPodcastSeries = try await repo.podcastSeries(unsavedPodcast.feedURL)!
    #expect(fetchedPodcastSeries.episodes.count == 2)

  }

  @Test("that upsertPodcastEpisodes works when fetching existing")
  func testAddEpisodesFetchExisting() async throws {
    let insertedPodcast = try TestHelpers.unsavedPodcast()
    let insertedEpisode = try TestHelpers.unsavedEpisode()
    let unsavedEpisodeInsertedPodcast = try TestHelpers.unsavedEpisode()
    try await repo.insertSeries(insertedPodcast, unsavedEpisodes: [insertedEpisode])

    let unsavedPodcast = try TestHelpers.unsavedPodcast()
    let unsavedEpisode = try TestHelpers.unsavedEpisode()

    let allPodcasts = [insertedPodcast, unsavedPodcast]
    let allEpisodes = [insertedEpisode, unsavedEpisodeInsertedPodcast, unsavedEpisode]

    let podcastEpisodes = try await repo.upsertPodcastEpisodes(
      [
        UnsavedPodcastEpisode(
          unsavedPodcast: insertedPodcast,
          unsavedEpisode: insertedEpisode
        ),
        UnsavedPodcastEpisode(
          unsavedPodcast: insertedPodcast,
          unsavedEpisode: unsavedEpisodeInsertedPodcast
        ),
        UnsavedPodcastEpisode(
          unsavedPodcast: unsavedPodcast,
          unsavedEpisode: unsavedEpisode
        ),
      ]
    )
    #expect(podcastEpisodes.count == 3)
    #expect(Set(podcastEpisodes.map(\.podcast.feedURL)) == Set(allPodcasts.map(\.feedURL)))
    #expect(Set(podcastEpisodes.map(\.episode.media)) == Set(allEpisodes.map(\.media)))

    var fetchedPodcastEpisodes: [PodcastEpisode] = []
    for podcastEpisode in podcastEpisodes {
      fetchedPodcastEpisodes.append(try await repo.episode(podcastEpisode.id)!)
    }
    #expect(Set(podcastEpisodes) == Set(fetchedPodcastEpisodes))
  }
}
