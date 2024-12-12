// Copyright Justin Bishop, 2024

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of Episode model tests")
actor Episode {
  private let repository: PodcastRepository

  init() {
    repository = PodcastRepository.empty()
  }

  @Test("that an episode can be created, fetched, updated, and deleted")
  func createSingleEpisode() async throws {
    let url = URL(string: "https://example.com/data")!
    let unsavedPodcast = try UnsavedPodcast(feedURL: url, title: "Title")
    let podcast = try await repository.insert(unsavedPodcast)
    #expect(podcast.title == unsavedPodcast.title)

    let newestUnsavedEpisode = UnsavedEpisode(guid: "guid", podcast: podcast)
    let oldestUnsavedEpisode = UnsavedEpisode(
      guid: "guid2",
      podcast: podcast,
      pubDate: Calendar.current.date(byAdding: .day, value: -10, to: Date())
    )
    let middleUnsavedEpisode = UnsavedEpisode(
      guid: "guid3",
      podcast: podcast,
      pubDate: Calendar.current.date(byAdding: .day, value: -5, to: Date())
    )
    try await repository.batchInsert([
      middleUnsavedEpisode, oldestUnsavedEpisode, newestUnsavedEpisode,
    ])

    let podcastSeries = try await repository.db.read { db in
      try Podcast
        .filter(id: podcast.id)
        .including(all: Podcast.episodes)
        .asRequest(of: PodcastSeries.self)
        .fetchOne(db)
    }!
    #expect(podcastSeries.podcast == podcast)
    #expect(
      (podcastSeries.episodes.map { Int($0.pubDate.timeIntervalSince1970) }) == [
        Int(newestUnsavedEpisode.pubDate.timeIntervalSince1970),
        Int(middleUnsavedEpisode.pubDate.timeIntervalSince1970),
        Int(oldestUnsavedEpisode.pubDate.timeIntervalSince1970),
      ]
    )
  }
}
