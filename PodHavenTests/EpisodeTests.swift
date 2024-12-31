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

    let newestUnsavedEpisode = try UnsavedEpisode(guid: "guid", media: url)
    let oldUnsavedEpisode = try UnsavedEpisode(
      guid: "guid2",
      media: url,
      pubDate: Calendar.current.date(byAdding: .day, value: -10, to: Date())
    )
    let middleUnsavedEpisode = try UnsavedEpisode(
      guid: "guid3",
      media: url,
      pubDate: Calendar.current.date(byAdding: .day, value: -5, to: Date())
    )
    let ancientUnsavedEpisode = try UnsavedEpisode(
      guid: "guid4",
      media: url,
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
    let unsavedEpisode = try UnsavedEpisode(
      guid: guid,
      media: url,
      currentTime: cmTime
    )
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
    let unsavedPodcast = try UnsavedPodcast(
      feedURL: URL.valid(),
      title: "Title"
    )
    let unsavedEpisode = try UnsavedEpisode(
      guid: String.random(),
      media: URL.valid()
    )
    try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [unsavedEpisode]
    )

    let podcastEpisode = try await repo.episode(unsavedEpisode.media)!
    #expect(podcastEpisode.episode.media == unsavedEpisode.media)
  }

  @Test("that an episode can be marked complete")
  func markEpisodeComplete() async throws {
    let unsavedPodcast = try UnsavedPodcast(
      feedURL: URL.valid(),
      title: "Title"
    )
    let unsavedEpisode = try UnsavedEpisode(
      guid: String.random(),
      media: URL.valid(),
      currentTime: CMTime.inSeconds(60)
    )
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
}
