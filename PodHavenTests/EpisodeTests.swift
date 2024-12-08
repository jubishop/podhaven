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
    let podcast = try repository.insert(unsavedPodcast)
    #expect(podcast.title == unsavedPodcast.title)

    let unsavedEpisode = UnsavedEpisode(guid: "guid", podcast: podcast)
    let episode = try repository.insert(unsavedEpisode)
    let episodes = try await repository.db.read { [podcast] db in
      try podcast.episodes.fetchAll(db)
    }
    #expect(episodes == [episode])

    let fetchedPodcast = try await repository.db.read { db in
      try episode.podcast.fetchOne(db)
    }
    #expect(podcast == fetchedPodcast)

    let olderUnsavedEpisode = UnsavedEpisode(
      guid: "guid2",
      podcast: podcast,
      pubDate: Calendar.current.date(byAdding: .day, value: -10, to: Date())
    )
    let olderEpisode = try repository.insert(olderUnsavedEpisode)
    let middleUnsavedEpisode = UnsavedEpisode(
      guid: "guid3",
      podcast: podcast,
      pubDate: Calendar.current.date(byAdding: .day, value: -5, to: Date())
    )
    let middleEpisode = try repository.insert(middleUnsavedEpisode)
    let podcastSeries = try await repository.db.read { db in
      try Podcast
        .including(all: Podcast.episodes)
        .asRequest(of: PodcastSeries.self)
        .filter(key: ["id": podcast.id])
        .fetchOne(db)
    }!
    #expect(podcastSeries.podcast == podcast)
    #expect(podcastSeries.episodes == [episode, middleEpisode, olderEpisode])
  }
}
