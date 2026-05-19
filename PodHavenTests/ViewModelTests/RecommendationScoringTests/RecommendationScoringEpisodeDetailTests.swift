// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

// Regression tests for the recommendation-score fan-out OOM (issue #274).
@Suite("of recommendation scoring EpisodeDetailViewModel tests", .container)
@MainActor final class RecommendationScoringEpisodeDetailTests {
  @DynamicInjected(\.recommendationEngine) private var recommendationEngine
  @DynamicInjected(\.recommendationRepo) private var recommendationRepo
  @DynamicInjected(\.repo) private var repo

  private var fakeRecommendationRepo: FakeRecommendationRepo {
    recommendationRepo as! FakeRecommendationRepo
  }

  @Test(
    "EpisodeDetailViewModel surfaces .computing on displayedScore while a fetch is in flight and replaces it on completion"
  )
  func episodeDetailScoringIndicatorToggles() async throws {
    let embeddable = RecommendationScoringTestHelpers.scoringEmbeddable()
    try await RecommendationScoringTestHelpers.primeEngine(with: embeddable)

    let (_, candidateEpisodes) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 1,
      podcastTitle: "Target",
      podcastDescription: "Target",
      episodeDescriptions: ["Target 0"]
    )
    try await RecommendationHelpers.embedEpisodes(candidateEpisodes, embeddable: embeddable)
    _ = try await RecommendationHelpers.startAndWaitForScores(for: candidateEpisodes)

    let targetEpisodeID = try #require(candidateEpisodes.first?.id)
    let podcastEpisode = try #require(try await repo.podcastEpisode(targetEpisodeID))

    let fakeRepo = fakeRecommendationRepo
    fakeRepo.armEmbeddingsGate(matching: Set([targetEpisodeID]))

    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(podcastEpisode))
    try await viewModel.performAppear()

    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { @MainActor in
        if case .computing = viewModel.displayedScore { return true }
        return false
      },
      { @MainActor in
        """
        Expected displayedScore to be .computing while the fetch is in flight.
        actual: \(String(describing: viewModel.displayedScore))
        """
      }
    )

    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { fakeRepo.isEmbeddingsGateSuspended },
      { "Expected scoring fetch to suspend on the gated embeddings call." }
    )

    fakeRepo.releaseEmbeddingsGate()

    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { @MainActor in
        if case .recommendation = viewModel.displayedScore { return true }
        return false
      },
      { @MainActor in
        """
        Expected displayedScore to settle on .recommendation once the fetch completes.
        actual: \(String(describing: viewModel.displayedScore))
        """
      }
    )
  }

  @Test(
    "EpisodeDetailViewModel observes the first contextRevision emitted immediately after recommendation observation starts"
  )
  func episodeDetailDoesNotDropFirstContextRevisionAfterObservationStarts() async throws {
    let embeddable = RecommendationScoringTestHelpers.scoringEmbeddable()
    try await RecommendationScoringTestHelpers.primeEngine(with: embeddable)

    let (_, candidateEpisodes) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 1,
      podcastTitle: "Target",
      podcastDescription: "Target",
      episodeDescriptions: ["Target 0"]
    )
    try await RecommendationHelpers.embedEpisodes(candidateEpisodes, embeddable: embeddable)
    _ = try await RecommendationHelpers.startAndWaitForScores(for: candidateEpisodes)

    let targetEpisodeID = try #require(candidateEpisodes.first?.id)
    let podcastEpisode = try #require(try await repo.podcastEpisode(targetEpisodeID))

    let fakeRepo = fakeRecommendationRepo
    let targetIDs = Set([targetEpisodeID])
    fakeRepo.armEmbeddingsGate(matching: targetIDs)

    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(podcastEpisode))
    try await viewModel.performAppear()

    recommendationEngine.$contextRevision.update { $0 += 1 }

    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { fakeRepo.isEmbeddingsGateSuspended },
      { "Expected bootstrap scoring to suspend before releasing it." }
    )

    fakeRecommendationRepo.clearAllCalls()
    fakeRepo.releaseEmbeddingsGate()

    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      {
        await MainActor.run {
          RecommendationScoringTestHelpers.scopedEmbeddingsCallCount(matching: targetIDs) >= 1
        }
      },
      {
        await MainActor.run {
          """
          Expected the first post-start contextRevision to schedule a trailing \
          refresh after the gated bootstrap pass completed.
          calls: \(RecommendationScoringTestHelpers.scopedEmbeddingsCallCount(matching: targetIDs))
          displayedScore: \(String(describing: viewModel.displayedScore))
          """
        }
      }
    )
  }

  @Test(
    "EpisodeDetailViewModel drops a stale bootstrap recommendation if a newer context refresh publishes first"
  )
  func episodeDetailStaleContextFetchDoesNotOverwriteNewerScore() async throws {
    Container.shared.userSettings().$recommendationDeconeMode.new(.focused)
    Container.shared.userSettings().$podcastAffinityWeight.new(0)

    let embeddable = MutableScriptedEmbeddable { text in
      if text.contains("Anchor") { return [0, 1, 0] }
      if text.contains("Old Signal") { return [1, 0, 0] }
      if text.contains("Fresh Signal") { return [0, 1, 0] }
      if text.contains("Target") { return [0, 1, 0] }
      return [0, 0, 1]
    }

    let (_, oldSignals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Old Signal",
      podcastDescription: "Old Signal",
      episodeDescriptions: Array(repeating: "Old Signal", count: 3),
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(oldSignals, embeddable: embeddable.scripted)
    _ = try await RecommendationHelpers.startAndWaitForScores(for: oldSignals)

    let (_, candidateEpisodes) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Target",
      podcastDescription: "Target",
      episodeDescriptions: ["Target", "Anchor"],
      pubDateOffset: { index in index == 0 ? -90 * 86400 : 0 }
    )
    try await RecommendationHelpers.embedEpisodes(
      candidateEpisodes,
      embeddable: embeddable.scripted
    )
    let targetEpisode = try #require(candidateEpisodes.first)
    let targetID = targetEpisode.id
    _ = try await RecommendationHelpers.startAndWaitForScores(for: candidateEpisodes)

    let podcastEpisode = try #require(try await repo.podcastEpisode(targetID))
    let fakeRepo = fakeRecommendationRepo
    fakeRepo.armEmbeddingsGate(matching: Set([targetID]))

    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(podcastEpisode))
    try await viewModel.performAppear()

    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { fakeRepo.isEmbeddingsGateSuspended },
      { "Expected the bootstrap recommendation fetch to suspend." }
    )

    let (_, freshSignals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 12,
      podcastTitle: "Fresh Signal",
      podcastDescription: "Fresh Signal",
      episodeDescriptions: Array(repeating: "Fresh Signal", count: 12),
      ratings: Array(repeating: .loved, count: 12)
    )
    try await RecommendationHelpers.embedEpisodes(freshSignals, embeddable: embeddable.scripted)

    let freshScore: Float = try await RecommendationHelpers.waitAdvancing {
      await MainActor.run {
        guard case .recommendation(let score) = viewModel.displayedScore else {
          return nil
        }
        return score.value
      }
    }

    fakeRepo.releaseEmbeddingsGate()
    try await Wait.until(
      priority: .userInitiated,
      { fakeRepo.didEmbeddingsGateComplete },
      { "Expected the stale bootstrap embeddings call to complete after release." }
    )
    await Task.yield()

    guard case .recommendation(let finalScore) = viewModel.displayedScore else {
      Issue.record(
        "Expected final displayedScore to remain a recommendation, got \(String(describing: viewModel.displayedScore))"
      )
      return
    }
    #expect(
      abs(finalScore.value - freshScore) < 0.001,
      """
      The stale bootstrap fetch overwrote the newer context-refresh score.
      freshScore: \(freshScore)
      finalScore: \(finalScore.value)
      """
    )
  }
}

private final class MutableScriptedEmbeddable: @unchecked Sendable {
  private let vectorFor = ThreadSafe<@Sendable (String) -> [Double]>({ _ in [0, 0, 1] })

  let scripted: ScriptedEmbeddable

  init(initial: @escaping @Sendable (String) -> [Double]) {
    vectorFor(initial)
    let vectorForBox = vectorFor
    scripted = ScriptedEmbeddable { text in
      vectorForBox()(text)
    }
  }

  func swap(_ next: @escaping @Sendable (String) -> [Double]) {
    vectorFor(next)
  }
}
