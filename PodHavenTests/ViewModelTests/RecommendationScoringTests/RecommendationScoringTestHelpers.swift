// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@MainActor enum RecommendationScoringTestHelpers {
  private static var fakeRecommendationRepo: FakeRecommendationRepo {
    Container.shared.recommendationRepo() as! FakeRecommendationRepo
  }

  private static var fakeSleeper: FakeSleeper {
    Container.shared.sleeper() as! FakeSleeper
  }

  static func scoringEmbeddable() -> ScriptedEmbeddable {
    ScriptedEmbeddable { text in
      if text.contains("Filler") { return [0, 0, 1] }
      if text.contains("Signal") { return [1, 0, 0] }
      if text.contains("Target 0") { return [0.2, 0.98, 0] }
      if text.contains("Target 1") { return [0.4, 0.917, 0] }
      if text.contains("Target 2") { return [0.6, 0.8, 0] }
      if text.contains("Target 3") { return [0.8, 0.6, 0] }
      if text.contains("Target") { return [0, 1, 0] }
      return [0, 0, 1]
    }
  }

  static func primeEngine(with embeddable: ScriptedEmbeddable) async throws {
    Container.shared.userSettings().$recommendationDeconeMode.new(.focused)

    let (_, fillers) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 10,
      podcastTitle: "Filler",
      podcastDescription: "Filler",
      episodeDescriptions: Array(repeating: "Filler", count: 10),
      ratings: Array(repeating: .notInterested, count: 10)
    )
    try await RecommendationHelpers.embedEpisodes(fillers, embeddable: embeddable)

    let (_, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      podcastDescription: "Signal",
      episodeDescriptions: ["Signal", "Signal", "Signal"],
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signals, embeddable: embeddable)
    _ = try await RecommendationHelpers.startAndWaitForScores(for: signals)
  }

  static func scopedEmbeddingsCallCount(matching ids: Set<Episode.ID>) -> Int {
    fakeRecommendationRepo.calls(of: MethodCall<[Episode.ID]>.self)
      .filter { $0.methodName == "embeddings" && Set($0.parameters) == ids }
      .count
  }

  static func waitForScopedEmbeddingsCalls(
    matching ids: Set<Episode.ID>,
    atLeast expectedCount: Int,
    reason: String
  ) async throws {
    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      {
        await MainActor.run {
          scopedEmbeddingsCallCount(matching: ids) >= expectedCount
        }
      },
      {
        await MainActor.run {
          """
          \(reason)
          expected: >= \(expectedCount)
          actual: \(scopedEmbeddingsCallCount(matching: ids))
          """
        }
      }
    )
  }

  // Asserts no candidate-scoped scoring pass runs within a bounded window.
  // Drives the production sleeper each round so any debounced rescore is forced
  // to fire, then watches for the first `embeddings(for:)` read whose ID set
  // equals `ids`. A hit records `regression`; the expected timeout means the
  // surface reused its retained score and ran no pass. Deterministic stand-in
  // for a fixed `Task.yield()` settle window when asserting this negative.
  static func expectNoScopedEmbeddings(
    matching ids: Set<Episode.ID>,
    maxAttempts: Int = 100,
    regression: String
  ) async {
    do {
      try await Wait.until(
        maxAttempts: maxAttempts,
        delay: .milliseconds(20),
        priority: .userInitiated,
        {
          await fakeSleeper.advanceTime(by: .milliseconds(400))
          return await MainActor.run { scopedEmbeddingsCallCount(matching: ids) >= 1 }
        },
        { "regression sentinel — see Issue.record below" }
      )
      Issue.record("\(regression)")
    } catch {
      // Expected timeout: no candidate-scoped pass ran.
    }
  }

  // Drains every cache rebuild the setup writes kicked off, polling until the
  // engine's `$scoringRevision` holds steady across `stableRounds` consecutive
  // drains. Tests that deliberately strand a scoring pass need this: a late
  // rebuild's `$scoringRevision` bump would otherwise reschedule the pass and
  // mask the regression under test.
  static func settleRecommendationEngine(stableRounds: Int = 20) async throws {
    let engine = Container.shared.recommendationEngine()
    let progress = ThreadSafe<(revision: Int, stable: Int)>((revision: Int.min, stable: 0))
    try await Wait.until(
      priority: .userInitiated,
      {
        await drainRecommendationSleeper()
        let current = engine.scoringRevision
        return progress { box in
          if current == box.revision {
            box.stable += 1
          } else {
            box.revision = current
            box.stable = 0
          }
          return box.stable >= stableRounds
        }
      },
      { "Expected the recommendation engine's $scoringRevision to quiesce." }
    )
  }

  // `duration` must exceed RecommendationEngine's debounce window so each round
  // fires whatever rebuild is currently armed.
  static func drainRecommendationSleeper(
    by duration: Duration = .seconds(6),
    maxRounds: Int = 20
  ) async {
    var idleRounds = 0
    for _ in 0..<maxRounds {
      await fakeSleeper.advanceTime(by: duration)
      for _ in 0..<3 {
        await Task.yield()
      }
      if fakeSleeper.pendingCount() == 0 {
        idleRounds += 1
        if idleRounds >= 2 { return }
      } else {
        idleRounds = 0
      }
    }
  }

  nonisolated static func recommendationOrder(
    _ episodes: [Episode],
    scores: [Episode.ID: RecommendationScore]
  ) -> [Episode.ID] {
    episodes
      .sorted { lhs, rhs in
        let lhsScore = scores[lhs.id]?.value ?? 0
        let rhsScore = scores[rhs.id]?.value ?? 0
        if lhsScore != rhsScore { return lhsScore > rhsScore }
        if lhs.pubDate != rhs.pubDate { return lhs.pubDate > rhs.pubDate }
        if lhs.mediaGUID.guid != rhs.mediaGUID.guid {
          return lhs.mediaGUID.guid > rhs.mediaGUID.guid
        }
        return lhs.mediaGUID.mediaURL.rawValue.absoluteString
          > rhs.mediaGUID.mediaURL.rawValue.absoluteString
      }
      .map(\.id)
  }
}
