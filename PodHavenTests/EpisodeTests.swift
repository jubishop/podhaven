// Copyright Justin Bishop, 2024

import AVFoundation
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of Episode model tests")
actor EpisodeTests {
  private let repo: Repo

  init() {
    repo = Repo.empty()
  }

  @Test("that episodes are created and fetched in the right order")
  func createSingleEpisode() async throws {
    let url = URL(string: "https://example.com/data")!
    let unsavedPodcast = try UnsavedPodcast(feedURL: url, title: "Title")

    let newestUnsavedEpisode = UnsavedEpisode(guid: "guid")
    let oldUnsavedEpisode = UnsavedEpisode(
      guid: "guid2",
      pubDate: Calendar.current.date(byAdding: .day, value: -10, to: Date())
    )
    let middleUnsavedEpisode = UnsavedEpisode(
      guid: "guid3",
      pubDate: Calendar.current.date(byAdding: .day, value: -5, to: Date())
    )
    let ancientUnsavedEpisode = UnsavedEpisode(
      guid: "guid4",
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
        .filter(key: ["feedURL": url])
        .including(all: Podcast.episodes)
        .asRequest(of: PodcastSeries.self)
        .fetchOne(db)
    }!
    #expect(
      podcastSeries.episodes.elements
        == podcastSeries.episodes.sorted { $0.pubDate > $1.pubDate }
    )
  }

  @Test("that episodes can persist currentTime")
  func persistCurrentTime() async throws {
    let url = URL(string: "https://example.com/data")!
    let guid = "guid"
    let cmTime = CMTime.inSeconds(30)

    let unsavedPodcast = try UnsavedPodcast(feedURL: url, title: "Title")
    let unsavedEpisode = UnsavedEpisode(
      guid: guid,
      media: url,
      currentTime: cmTime
    )
    let podcast = try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [unsavedEpisode]
    )

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

  @Test("that the queueOrder works")
  func testQueueOrder() async throws {
    let url = URL(string: "https://example.com/data")!
    let unsavedPodcast = try UnsavedPodcast(feedURL: url, title: "Title")

    // General insertion testing
    let topUnsavedEpisode = UnsavedEpisode(guid: "top", queueOrder: 1)
    let bottomUnsavedEpisode = UnsavedEpisode(guid: "bot", queueOrder: 4)
    let midTopUnsavedEpisode = UnsavedEpisode(guid: "midto", queueOrder: 2)
    let midBottomUnsavedEpisode = UnsavedEpisode(guid: "midbo", queueOrder: 3)
    let unqueuedBottomEpisode = UnsavedEpisode(guid: "unqbo")
    let unqueuedTopEpisode = UnsavedEpisode(guid: "unqto")
    let podcast = try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [
        topUnsavedEpisode,
        bottomUnsavedEpisode,
        midTopUnsavedEpisode,
        midBottomUnsavedEpisode,
        unqueuedBottomEpisode,
        unqueuedTopEpisode,
      ]
    )
    var podcastEpisodes = try await repo.db.read { db in
      try Episode
        .filter(Column("queueOrder") != nil)
        .including(required: Episode.podcast)
        .order(Column("queueOrder").asc)
        .asRequest(of: PodcastEpisode.self)
        .fetchAll(db)
    }
    #expect(podcastEpisodes.map { $0.episode.queueOrder } == [1, 2, 3, 4])

    // Testing appending at bottom
    let newBottomEpisode = try await repo.db.read { db in
      try Episode.fetchOne(db, key: ["guid": "unqbo", "podcastId": podcast.id])
    }!
    try await repo.appendToQueue(newBottomEpisode.id)
    let newMaxEpisode = try await repo.db.read { db in
      try Episode.find(db, id: newBottomEpisode.id)
    }
    #expect(newMaxEpisode.queueOrder == 5)

    // Test inserting at top
    let newTopEpisode = try await repo.db.read { db in
      try Episode.fetchOne(db, key: ["guid": "unqto", "podcastId": podcast.id])
    }!
    try await repo.insertToQueue(newTopEpisode.id, at: 1)
    let newMinEpisode = try await repo.db.read { db in
      try Episode.find(db, id: newTopEpisode.id)
    }
    #expect(newMinEpisode.queueOrder == 1)
    var updatedMaxEpisode = try await repo.db.read { db in
      try Episode.find(db, id: newBottomEpisode.id)
    }
    #expect(updatedMaxEpisode.queueOrder == 6)
    podcastEpisodes = try await repo.db.read { db in
      try Episode
        .filter(Column("queueOrder") != nil)
        .including(required: Episode.podcast)
        .order(Column("queueOrder").asc)
        .asRequest(of: PodcastEpisode.self)
        .fetchAll(db)
    }
    #expect(
      podcastEpisodes.map { $0.episode.queueOrder } == [1, 2, 3, 4, 5, 6]
    )

    // Test dequeuing an item in the middle
    var midTopEpisode = try await repo.db.read { db in
      try Episode.fetchOne(db, key: ["guid": "midto", "podcastId": podcast.id])
    }!
    try await repo.dequeue(midTopEpisode.id)
    midTopEpisode = try await repo.db.read { db in
      try Episode.fetchOne(db, key: ["guid": "midto", "podcastId": podcast.id])
    }!
    #expect(midTopEpisode.queueOrder == nil)
    updatedMaxEpisode = try await repo.db.read { db in
      try Episode.find(db, id: newBottomEpisode.id)
    }
    #expect(updatedMaxEpisode.queueOrder == 5)
    podcastEpisodes = try await repo.db.read { db in
      try Episode
        .filter(Column("queueOrder") != nil)
        .including(required: Episode.podcast)
        .order(Column("queueOrder").asc)
        .asRequest(of: PodcastEpisode.self)
        .fetchAll(db)
    }
    #expect(
      podcastEpisodes.map { $0.episode.queueOrder } == [1, 2, 3, 4, 5]
    )

    // TODO: Test when oldPositions exist
  }
}
