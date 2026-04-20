// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("Episode rating tests", .container)
class EpisodeRatingTests {
  @DynamicInjected(\.appDB) private var appDB
  @DynamicInjected(\.repo) private var repo

  // MARK: - Helpers

  private func createPodcastWithEpisode(
    rating: EpisodeRating? = nil,
    ratingDate: Date? = nil
  ) async throws -> Episode {
    let unsavedPodcast = try Create.unsavedPodcast()
    let unsavedEpisode = try Create.unsavedEpisode(rating: rating, ratingDate: ratingDate)

    let podcastEpisodes = try await repo.upsertPodcastEpisodes([
      UnsavedPodcastEpisode(unsavedPodcast: unsavedPodcast, unsavedEpisode: unsavedEpisode)
    ])
    return podcastEpisodes.first!.episode
  }

  // MARK: - Persistence

  @Test("rating persists through save and fetch")
  func ratingPersistence() async throws {
    let episode = try await createPodcastWithEpisode(rating: .loved, ratingDate: Date())
    #expect(episode.rating == .loved)
    #expect(episode.ratingDate != nil)
  }

  @Test("nil rating persists as unrated")
  func nilRatingPersistence() async throws {
    let episode = try await createPodcastWithEpisode()
    #expect(episode.rating == nil)
    #expect(episode.ratingDate == nil)
  }

  // MARK: - Update Rating

  @Test("updateRating sets rating and ratingDate")
  func updateRating() async throws {
    let episode = try await createPodcastWithEpisode()

    try await repo.updateRating(episode.id, rating: .liked)

    let updated = try await repo.episode(episode.id)!
    #expect(updated.rating == .liked)
    #expect(updated.ratingDate != nil)
  }

  @Test("updateRating toggles off by setting nil")
  func updateRatingToggle() async throws {
    let episode = try await createPodcastWithEpisode(rating: .liked, ratingDate: Date())

    try await repo.updateRating(episode.id, rating: nil)

    let updated = try await repo.episode(episode.id)!
    #expect(updated.rating == nil)
    #expect(updated.ratingDate == nil)
  }

  @Test("updateRating upgrades from liked to loved and resets ratingDate")
  func updateRatingUpgrade() async throws {
    let originalDate = Date().addingTimeInterval(-3600)
    let episode = try await createPodcastWithEpisode(rating: .liked, ratingDate: originalDate)

    try await repo.updateRating(episode.id, rating: .loved)

    let updated = try await repo.episode(episode.id)!
    #expect(updated.rating == .loved)
    #expect(updated.ratingDate! > originalDate)
  }

  // MARK: - SQL Expressions

  @Test("SQL expressions filter correctly")
  func sqlExpressions() async throws {
    let lovedEpisode = try await createPodcastWithEpisode(rating: .loved, ratingDate: Date())
    let likedEpisode = try await createPodcastWithEpisode(rating: .liked, ratingDate: Date())
    let dislikedEpisode = try await createPodcastWithEpisode(rating: .disliked, ratingDate: Date())
    _ = try await createPodcastWithEpisode()

    let loved = try await repo.db.read { db in
      try Episode.filter(Episode.loved).fetchAll(db)
    }
    #expect(loved.count == 1)
    #expect(loved.first?.id == lovedEpisode.id)

    let liked = try await repo.db.read { db in
      try Episode.filter(Episode.liked).fetchAll(db)
    }
    #expect(liked.count == 1)
    #expect(liked.first?.id == likedEpisode.id)

    let disliked = try await repo.db.read { db in
      try Episode.filter(Episode.disliked).fetchAll(db)
    }
    #expect(disliked.count == 1)
    #expect(disliked.first?.id == dislikedEpisode.id)

    let rated = try await repo.db.read { db in
      try Episode.filter(Episode.rated).fetchAll(db)
    }
    #expect(rated.count == 3)
  }

  // MARK: - CHECK Constraint

  @Test("CHECK constraint rejects invalid rating values")
  func checkConstraint() async throws {
    let episode = try await createPodcastWithEpisode()

    await #expect(throws: DatabaseError.self) {
      _ = try await self.appDB.db.write { db in
        try Episode
          .withID(episode.id)
          .updateAll(db, Episode.Columns.rating.set(to: "invalid"))
      }
    }
  }

  // Locks the EpisodeRating rawValue set to match the v35 migration's hardcoded
  // CHECK constraint. Adding/renaming a case without a follow-up migration to
  // widen the constraint would cause silent runtime write failures.
  @Test("EpisodeRating rawValues match v35 CHECK constraint")
  func ratingRawValuesMatchCheckConstraint() {
    let expected: Set<String> = ["loved", "liked", "disliked"]
    #expect(Set(EpisodeRating.allCases.map(\.rawValue)) == expected)
  }

  // MARK: - Signal Episodes

  @Test("fetchSignalEpisodes returns rated and finished episodes")
  func fetchSignalEpisodes() async throws {
    _ = try await createPodcastWithEpisode(rating: .loved, ratingDate: Date())
    _ = try await createPodcastWithEpisode(rating: .disliked, ratingDate: Date())

    let unsavedPodcast = try Create.unsavedPodcast()
    let finishedEpisode = try Create.unsavedEpisode(finishDate: Date())
    _ = try await repo.upsertPodcastEpisodes([
      UnsavedPodcastEpisode(unsavedPodcast: unsavedPodcast, unsavedEpisode: finishedEpisode)
    ])

    _ = try await createPodcastWithEpisode()

    let signals = try await repo.allSignalEpisodes()
    #expect(signals.count == 3)
  }
}
