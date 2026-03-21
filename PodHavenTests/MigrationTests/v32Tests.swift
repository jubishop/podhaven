// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("v32 migration tests (episode rating columns)", .container)
class V32MigrationTests {
  @DynamicInjected(\.appDB) private var appDB
  @DynamicInjected(\.repo) private var repo

  @Test("v32 adds rating and ratingDate columns to episode table")
  func ratingColumnsExist() async throws {
    let columns = try await appDB.db.read { db in
      try db.columns(in: "episode").map(\.name)
    }
    #expect(columns.contains("rating"))
    #expect(columns.contains("ratingDate"))
  }

  @Test("rating column accepts valid values")
  func ratingColumnValues() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()

    for rating in EpisodeRating.allCases {
      let episode = try Create.unsavedEpisode(rating: rating, ratingDate: Date())
      _ = try await repo.upsertPodcastEpisodes([
        UnsavedPodcastEpisode(unsavedPodcast: unsavedPodcast, unsavedEpisode: episode)
      ])
    }

    let episodes = try await repo.db.read { db in
      try Episode.filter(Episode.rated).fetchAll(db)
    }
    #expect(episodes.count == 3)
  }
}

extension EpisodeRating: @retroactive CaseIterable {
  public static var allCases: [EpisodeRating] { [.loved, .liked, .disliked] }
}
