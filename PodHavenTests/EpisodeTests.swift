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
  }
}
