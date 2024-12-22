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

    var episode = try await repo.db.read { db in
      try Episode.fetchOne(db, key: ["guid": guid, "podcastId": podcast.id])
    }!
    #expect(episode.currentTime == cmTime)

    let newCMTime = CMTime.inSeconds(60)
    episode.currentTime = newCMTime
    try await repo.update(episode)

    episode = try await repo.db.read { db in
      try Episode.fetchOne(db, key: ["guid": guid, "podcastId": podcast.id])
    }!
    #expect(episode.currentTime == newCMTime)
  }

  @Test("that episodes can persist and fetch queueOrder")
  func persistQueueOrder() async throws {
    let url = URL(string: "https://example.com/data")!
    let unsavedPodcast = try UnsavedPodcast(feedURL: url, title: "Title")

    let topUnsavedEpisode = UnsavedEpisode(guid: "guid", queueOrder: 0)
    let bottomUnsavedEpisode = UnsavedEpisode(
      guid: "guid2",
      queueOrder: 3
    )
    let middleTopUnsavedEpisode = UnsavedEpisode(
      guid: "guid3",
      queueOrder: 1
    )
    let middleBottomUnsavedEpisode = UnsavedEpisode(
      guid: "guid4",
      queueOrder: 2
    )

    try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [
        topUnsavedEpisode,
        bottomUnsavedEpisode,
        middleTopUnsavedEpisode,
        middleBottomUnsavedEpisode,
      ]
    )

    let podcastEpisodes = try await repo.db.read { db in
      try Episode
        .filter(Column("queueOrder") != nil)
        .including(required: Episode.podcast)
        .order(Column("queueOrder").asc)
        .asRequest(of: PodcastEpisode.self)
        .fetchAll(db)
    }
    #expect(podcastEpisodes.map { $0.episode.queueOrder } == [0, 1, 2, 3])
  }
}
