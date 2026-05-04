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

  // MARK: - Bulk Update Rating

  @Test("bulk updateRating sets rating and ratingDate on all episodes")
  func bulkUpdateRatingSetsAll() async throws {
    let one = try await createPodcastWithEpisode()
    let two = try await createPodcastWithEpisode()
    let three = try await createPodcastWithEpisode()

    let updated = try await repo.updateRating([one.id, two.id, three.id], rating: .loved)
    #expect(updated == 3)

    for id in [one.id, two.id, three.id] {
      let fetched = try await repo.episode(id)!
      #expect(fetched.rating == .loved)
      #expect(fetched.ratingDate != nil)
    }
  }

  @Test("bulk updateRating with nil clears rating and ratingDate")
  func bulkUpdateRatingClearsAll() async throws {
    let one = try await createPodcastWithEpisode(rating: .loved, ratingDate: Date())
    let two = try await createPodcastWithEpisode(rating: .liked, ratingDate: Date())

    let updated = try await repo.updateRating([one.id, two.id], rating: nil)
    #expect(updated == 2)

    for id in [one.id, two.id] {
      let fetched = try await repo.episode(id)!
      #expect(fetched.rating == nil)
      #expect(fetched.ratingDate == nil)
    }
  }

  @Test("bulk updateRating returns 0 for empty array and runs no write")
  func bulkUpdateRatingEmpty() async throws {
    let count = try await repo.updateRating([], rating: .loved)
    #expect(count == 0)
  }

  @Test("bulk updateRating only touches the supplied IDs")
  func bulkUpdateRatingScoped() async throws {
    let target = try await createPodcastWithEpisode()
    let untouched = try await createPodcastWithEpisode(rating: .liked, ratingDate: Date())

    try await repo.updateRating([target.id], rating: .disliked)

    let updatedTarget = try await repo.episode(target.id)!
    #expect(updatedTarget.rating == .disliked)
    #expect(updatedTarget.ratingDate != nil)

    let untouchedAfter = try await repo.episode(untouched.id)!
    #expect(untouchedAfter.rating == .liked)
  }

  // MARK: - SQL Expressions

  @Test("SQL expressions filter correctly")
  func sqlExpressions() async throws {
    let lovedEpisode = try await createPodcastWithEpisode(rating: .loved, ratingDate: Date())
    let likedEpisode = try await createPodcastWithEpisode(rating: .liked, ratingDate: Date())
    let dislikedEpisode = try await createPodcastWithEpisode(rating: .disliked, ratingDate: Date())
    let notInterestedEpisode = try await createPodcastWithEpisode(
      rating: .notInterested,
      ratingDate: Date()
    )
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

    let notInterested = try await repo.db.read { db in
      try Episode.filter(Episode.notInterested).fetchAll(db)
    }
    #expect(notInterested.count == 1)
    #expect(notInterested.first?.id == notInterestedEpisode.id)

    let rated = try await repo.db.read { db in
      try Episode.filter(Episode.rated).fetchAll(db)
    }
    #expect(rated.count == 4)

    // notInterested is rated but contributes no signal: hasRatingSignal
    // (loved || liked || disliked) excludes it.
    let hasRatingSignal = try await repo.db.read { db in
      try Episode.filter(Episode.hasRatingSignal).fetchAll(db)
    }
    #expect(hasRatingSignal.count == 3)
    #expect(hasRatingSignal.contains { $0.id == notInterestedEpisode.id } == false)
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

  // Locks the EpisodeRating rawValue set to match the latest migration's
  // hardcoded CHECK constraint (currently v42, which widened v35 to include
  // 'notInterested'). Adding/renaming a case without a follow-up migration
  // would cause silent runtime write failures.
  @Test("EpisodeRating rawValues match v42 CHECK constraint")
  func ratingRawValuesMatchCheckConstraint() {
    let expected: Set<String> = ["loved", "liked", "disliked", "notInterested"]
    #expect(Set(EpisodeRating.allCases.map(\.rawValue)) == expected)
  }

  // MARK: - Signal Episodes

  @Test("allRatedEpisodes returns only rated episodes (finished alone is no longer signal)")
  func fetchSignalEpisodes() async throws {
    _ = try await createPodcastWithEpisode(rating: .loved, ratingDate: Date())
    _ = try await createPodcastWithEpisode(rating: .disliked, ratingDate: Date())

    // A finished-but-unrated episode is no longer a signal: next-button
    // finishes are too noisy to count, and a real engagement signal lives
    // in the playback-coverage bitmap (see PartialSignal).
    let unsavedPodcast = try Create.unsavedPodcast()
    let finishedEpisode = try Create.unsavedEpisode(finishDate: Date())
    _ = try await repo.upsertPodcastEpisodes([
      UnsavedPodcastEpisode(unsavedPodcast: unsavedPodcast, unsavedEpisode: finishedEpisode)
    ])

    _ = try await createPodcastWithEpisode()

    let signals = try await repo.allRatedEpisodes()
    #expect(signals.count == 2)

    let ratings = signals.map(\.rating)
    #expect(ratings.contains(.loved))
    #expect(ratings.contains(.disliked))
  }

  @Test("rated episodes appear in allRatedEpisodes regardless of finishDate")
  func ratedAndFinishedAppearAsRated() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    let bothRatedAndFinished = try Create.unsavedEpisode(
      finishDate: Date(),
      rating: .liked,
      ratingDate: Date()
    )
    _ = try await repo.upsertPodcastEpisodes([
      UnsavedPodcastEpisode(unsavedPodcast: unsavedPodcast, unsavedEpisode: bothRatedAndFinished)
    ])

    let signals = try await repo.allRatedEpisodes()
    #expect(signals.count == 1)
    #expect(signals.first?.rating == .liked)
  }

  // MARK: - Partial Signals

  @Test("allUnratedListenedEpisodes returns played-but-unrated episodes with their coverage ratio")
  func partialSignalsReturnsPlayedUnrated() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    let unsaved = try Create.unsavedEpisode(duration: CMTime.seconds(300))
    let pe = try await repo
      .upsertPodcastEpisodes([
        UnsavedPodcastEpisode(unsavedPodcast: unsavedPodcast, unsavedEpisode: unsaved)
      ])
      .first!

    try await repo.updatePlayback(
      pe.episode.id,
      currentTime: CMTime.seconds(150),
      playedFrom: CMTime.seconds(0),
      now: Date()
    )

    let partials = try await repo.allUnratedListenedEpisodes()
    let partial = try #require(partials.first { $0.id == pe.episode.id })
    #expect(abs(partial.coverageRatio - 0.5) < 0.05)
    #expect(partial.lastPlayedDate != nil)
    #expect(partial.podcastID == pe.episode.podcastID)
  }

  @Test("allUnratedListenedEpisodes excludes rated episodes (rating wins precedence)")
  func partialSignalsExcludesRated() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    let unsaved = try Create.unsavedEpisode(
      duration: CMTime.seconds(300),
      rating: .liked,
      ratingDate: Date()
    )
    let pe = try await repo
      .upsertPodcastEpisodes([
        UnsavedPodcastEpisode(unsavedPodcast: unsavedPodcast, unsavedEpisode: unsaved)
      ])
      .first!

    try await repo.updatePlayback(
      pe.episode.id,
      currentTime: CMTime.seconds(150),
      playedFrom: CMTime.seconds(0),
      now: Date()
    )

    let partials = try await repo.allUnratedListenedEpisodes()
    #expect(partials.contains { $0.id == pe.episode.id } == false)

    let signals = try await repo.allRatedEpisodes()
    #expect(signals.contains { $0.id == pe.episode.id })
  }

  @Test("allUnratedListenedEpisodes preserves bitmap across markFinished")
  func partialSignalsSurvivesFinish() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    let unsaved = try Create.unsavedEpisode(duration: CMTime.seconds(300))
    let pe = try await repo
      .upsertPodcastEpisodes([
        UnsavedPodcastEpisode(unsavedPodcast: unsavedPodcast, unsavedEpisode: unsaved)
      ])
      .first!

    try await repo.updatePlayback(
      pe.episode.id,
      currentTime: CMTime.seconds(270),
      playedFrom: CMTime.seconds(0),
      now: Date()
    )
    try await repo.markFinished(pe.episode.id)

    let partials = try await repo.allUnratedListenedEpisodes()
    let partial = try #require(partials.first { $0.id == pe.episode.id })
    #expect(partial.coverageRatio >= 0.85)
  }

  @Test("allUnratedListenedEpisodes excludes next-button finishes (no bitmap)")
  func partialSignalsExcludesNextButton() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    let unsaved = try Create.unsavedEpisode(
      duration: CMTime.seconds(300),
      finishDate: Date()
    )
    let pe = try await repo
      .upsertPodcastEpisodes([
        UnsavedPodcastEpisode(unsavedPodcast: unsavedPodcast, unsavedEpisode: unsaved)
      ])
      .first!

    let partials = try await repo.allUnratedListenedEpisodes()
    #expect(partials.contains { $0.id == pe.episode.id } == false)

    let signals = try await repo.allRatedEpisodes()
    #expect(signals.contains { $0.id == pe.episode.id } == false)
  }

  @Test("allUnratedListenedEpisodes excludes episodes below the absolute-seconds floor")
  func partialSignalsExcludesBelowAbsoluteFloor() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    // 200s episode played 0..30s: 30s covered (15% ratio passes the 10%
    // ratio floor) but coveredSeconds=30 is below the 60s absolute floor —
    // think autoplay-skip on a short episode.
    let unsaved = try Create.unsavedEpisode(duration: CMTime.seconds(200))
    let pe = try await repo
      .upsertPodcastEpisodes([
        UnsavedPodcastEpisode(unsavedPodcast: unsavedPodcast, unsavedEpisode: unsaved)
      ])
      .first!

    try await repo.updatePlayback(
      pe.episode.id,
      currentTime: CMTime.seconds(30),
      playedFrom: CMTime.seconds(0),
      now: Date()
    )

    let partials = try await repo.allUnratedListenedEpisodes()
    #expect(partials.contains { $0.id == pe.episode.id } == false)
  }

  @Test("allUnratedListenedEpisodes excludes episodes below the ratio floor")
  func partialSignalsExcludesBelowRatioFloor() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    // 1000s episode played 0..90s: coveredSeconds=90 passes the 60s
    // absolute floor but ratio=0.09 is below the 10% ratio floor —
    // think autoplay-skip on a long episode.
    let unsaved = try Create.unsavedEpisode(duration: CMTime.seconds(1000))
    let pe = try await repo
      .upsertPodcastEpisodes([
        UnsavedPodcastEpisode(unsavedPodcast: unsavedPodcast, unsavedEpisode: unsaved)
      ])
      .first!

    try await repo.updatePlayback(
      pe.episode.id,
      currentTime: CMTime.seconds(90),
      playedFrom: CMTime.seconds(0),
      now: Date()
    )

    let partials = try await repo.allUnratedListenedEpisodes()
    #expect(partials.contains { $0.id == pe.episode.id } == false)
  }

  @Test("allUnratedListenedEpisodes includes episodes that just clear both floors")
  func partialSignalsIncludesAtThreshold() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    // 600s episode played 0..60s: coveredSeconds=60 (==60 floor) and
    // ratio=0.10 (==10% floor). Both boundaries are inclusive.
    let unsaved = try Create.unsavedEpisode(duration: CMTime.seconds(600))
    let pe = try await repo
      .upsertPodcastEpisodes([
        UnsavedPodcastEpisode(unsavedPodcast: unsavedPodcast, unsavedEpisode: unsaved)
      ])
      .first!

    try await repo.updatePlayback(
      pe.episode.id,
      currentTime: CMTime.seconds(60),
      playedFrom: CMTime.seconds(0),
      now: Date()
    )

    let partials = try await repo.allUnratedListenedEpisodes()
    let partial = try #require(partials.first { $0.id == pe.episode.id })
    #expect(partial.coveredSeconds == 60)
    #expect(abs(partial.coverageRatio - 0.10) < 1e-9)
  }

  @Test("allScoringContextInputs aggregates rated and unrated-listened episodes")
  func allScoringContextAggregates() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    let rated = try Create.unsavedEpisode(
      duration: CMTime.seconds(300),
      rating: .loved,
      ratingDate: Date()
    )
    let listened = try Create.unsavedEpisode(duration: CMTime.seconds(300))
    let pes = try await repo.upsertPodcastEpisodes([
      UnsavedPodcastEpisode(unsavedPodcast: unsavedPodcast, unsavedEpisode: rated),
      UnsavedPodcastEpisode(unsavedPodcast: unsavedPodcast, unsavedEpisode: listened),
    ])
    let listenedID = try #require(
      pes.first { $0.episode.unsaved.guid == listened.guid }?.episode.id
    )
    try await repo.updatePlayback(
      listenedID,
      currentTime: CMTime.seconds(150),
      playedFrom: CMTime.seconds(0),
      now: Date()
    )

    let inputs = try await repo.allScoringContextInputs()
    #expect(inputs.ratedSignals.contains { $0.rating == .loved })
    #expect(inputs.partialSignals.contains { $0.id == listenedID })
  }

  // MARK: - Not Interested

  @Test("notInterested rating persists and is excluded from allRatedEpisodes")
  func notInterestedExcludedFromRatedSignals() async throws {
    let liked = try await createPodcastWithEpisode(rating: .liked, ratingDate: Date())
    let notInterested = try await createPodcastWithEpisode(
      rating: .notInterested,
      ratingDate: Date()
    )

    let fetched = try await repo.episode(notInterested.id)!
    #expect(fetched.rating == .notInterested)

    let signals = try await repo.allRatedEpisodes()
    let signalIDs = signals.map(\.id)
    #expect(signalIDs.contains(liked.id))
    #expect(signalIDs.contains(notInterested.id) == false)
  }

  @Test("notInterested rating excludes episode from candidate pool")
  func notInterestedExcludedFromCandidates() async throws {
    let candidate = try await createPodcastWithEpisode()
    let notInterested = try await createPodcastWithEpisode(
      rating: .notInterested,
      ratingDate: Date()
    )

    let candidates = try await repo.db.read { db in
      try Episode.filter(Episode.candidate).fetchAll(db)
    }
    let candidateIDs = candidates.map(\.id)
    #expect(candidateIDs.contains(candidate.id))
    #expect(candidateIDs.contains(notInterested.id) == false)
  }

  @Test("notInterested rating excludes played episode from partial signals")
  func notInterestedExcludedFromPartialSignals() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    let unsaved = try Create.unsavedEpisode(
      duration: CMTime.seconds(300),
      rating: .notInterested,
      ratingDate: Date()
    )
    let pe = try await repo
      .upsertPodcastEpisodes([
        UnsavedPodcastEpisode(unsavedPodcast: unsavedPodcast, unsavedEpisode: unsaved)
      ])
      .first!

    try await repo.updatePlayback(
      pe.episode.id,
      currentTime: CMTime.seconds(150),
      playedFrom: CMTime.seconds(0),
      now: Date()
    )

    let partials = try await repo.allUnratedListenedEpisodes()
    #expect(partials.contains { $0.id == pe.episode.id } == false)

    let signals = try await repo.allRatedEpisodes()
    #expect(signals.contains { $0.id == pe.episode.id } == false)
  }

  @Test("CHECK constraint accepts notInterested rating")
  func checkConstraintAcceptsNotInterested() async throws {
    let episode = try await createPodcastWithEpisode()

    _ = try await self.appDB.db.write { db in
      try Episode
        .withID(episode.id)
        .updateAll(db, Episode.Columns.rating.set(to: "notInterested"))
    }

    let updated = try await repo.episode(episode.id)!
    #expect(updated.rating == .notInterested)
  }
}
