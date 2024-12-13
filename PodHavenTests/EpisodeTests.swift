// Copyright Justin Bishop, 2024

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of Episode model tests")
actor EpisodeTests {
  private let repository: PodcastRepository

  init() {
    repository = PodcastRepository.empty()
  }

  @Test("that episodes are created and fetched in the right order")
  func createSingleEpisode() async throws {
    let url = URL(string: "https://example.com/data")!
    let unsavedPodcast = try UnsavedPodcast(feedURL: url, title: "Title")

    let newestUnsavedEpisode = UnsavedEpisode(guid: "guid")
    let oldestUnsavedEpisode = UnsavedEpisode(
      guid: "guid2",
      pubDate: Calendar.current.date(byAdding: .day, value: -10, to: Date())
    )
    let middleUnsavedEpisode = UnsavedEpisode(
      guid: "guid3",
      pubDate: Calendar.current.date(byAdding: .day, value: -5, to: Date())
    )

    try await repository.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [
        middleUnsavedEpisode, oldestUnsavedEpisode, newestUnsavedEpisode,
      ]
    )

    let podcastSeries = try await repository.db.read { db in
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
}
