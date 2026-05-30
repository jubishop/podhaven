// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("of EpisodeDetailViewModel scoring tests", .container)
@MainActor final class EpisodeDetailScoringTests {
  @DynamicInjected(\.repo) private var repo

  @Test("saved episode bootstraps a recommendation score and re-bootstraps after delete + re-save")
  func savedEpisodeBootstrapsRecommendationScoreAfterDeleteAndResave() async throws {
    let (_, signalEpisodes) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Detail Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signalEpisodes)

    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "Recommendation Delete Resave"),
        unsavedEpisode: try Create.unsavedEpisode(
          guid: "recommendation-delete-resave",
          title: "Recommendation Delete Resave"
        )
      )
    )
    try await RecommendationHelpers.embedEpisodes([podcastEpisode.episode])
    _ = try await RecommendationHelpers.startAndWaitForScores(for: [podcastEpisode.episode])

    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(podcastEpisode))

    viewModel.appear()

    try await Wait.until(
      { @MainActor in
        if case .recommendation = viewModel.displayedScore { return true }
        return false
      },
      { @MainActor in
        """
        Expected saved episode to bootstrap a recommendation-kind score.
        score: \(String(describing: viewModel.displayedScore))
        """
      }
    )

    _ = try await repo.deletePodcast(podcastEpisode.podcast.id)

    try await Wait.until(
      { @MainActor in !viewModel.episode.isSaved },
      { @MainActor in
        "Expected deleted saved episode to revert before re-saving. episode: \(viewModel.episode.toString)"
      }
    )

    viewModel.addToTopOfQueue()

    // The re-save inserts a new `Episode` row (new ID) without an embedding;
    // embed it once it lands so the saved-side scoring path can resolve.
    try await Wait.until(
      { @MainActor in viewModel.episode.isSaved },
      { @MainActor in
        "Expected re-save to land before embedding the re-created episode. saved: \(viewModel.episode.isSaved)"
      }
    )
    let resaved = try #require(
      try await repo.podcastEpisode(
        podcastEpisode.episode.mediaGUID,
        feedURL: podcastEpisode.feedURL
      )
    )
    try await RecommendationHelpers.embedEpisodes([resaved.episode])

    // Drive the engine's embedding-table observation through its 400ms
    // debounce so scoringRevision bumps and the saved-side fetch re-runs
    // with the newly-inserted embedding visible.
    _ = try await RecommendationHelpers.waitAdvancing {
      let isRecommendation = await MainActor.run {
        if case .recommendation = viewModel.displayedScore { return true }
        return false
      }
      return isRecommendation ? true : nil
    }
  }

  @Test("saved episode without an embedding surfaces an embedding-pending indicator")
  func savedEpisodeWithoutEmbeddingSurfacesEmbeddingPending() async throws {
    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "Pending Embedding"),
        unsavedEpisode: try Create.unsavedEpisode(
          guid: "pending-embedding",
          title: "Pending Embedding"
        )
      )
    )
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(podcastEpisode))

    viewModel.appear()

    try await Wait.until(
      { @MainActor in
        if case .embeddingPending = viewModel.displayedScore { return true }
        return false
      },
      { @MainActor in
        """
        Expected saved episode without an embedding to surface .embeddingPending.
        score: \(String(describing: viewModel.displayedScore))
        """
      }
    )
  }

  @Test("unsaved episode opened from search shows a similarity score without persisting")
  func unsavedEpisodeShowsSimilarityScoreWithoutPersisting() async throws {
    let (_, signalEpisodes) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Unsaved Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signalEpisodes)
    _ = try await RecommendationHelpers.startAndWaitForScores(for: signalEpisodes)

    let unsavedPodcastEpisode = UnsavedPodcastEpisode(
      unsavedPodcast: try Create.unsavedPodcast(
        title: "Discovery Podcast",
        description: "An undiscovered show similar to the signals"
      ),
      unsavedEpisode: try Create.unsavedEpisode(
        guid: "unsaved-similarity",
        title: "Discovery Episode",
        description: "An episode about topics the user likes"
      )
    )
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(unsavedPodcastEpisode))

    viewModel.appear()

    try await Wait.until(
      { @MainActor in
        if case .similarity = viewModel.displayedScore { return true }
        return false
      },
      { @MainActor in
        """
        Expected unsaved episode to show a similarity-kind score.
        score: \(String(describing: viewModel.displayedScore))
        """
      }
    )

    #expect(viewModel.episode.isSaved == false)
    #expect(
      try await repo.podcastEpisode(
        unsavedPodcastEpisode.mediaGUID,
        feedURL: unsavedPodcastEpisode.feedURL
      ) == nil
    )
  }

  @Test("unsaved episode hides the score when the engine cache is cold")
  func unsavedEpisodeHidesScoreWhenCacheIsCold() async throws {
    // Probe-then-assert pattern: no signals planted means similarityScore
    // returns nil for every tick, so waiting on a probe-observed vector
    // request is the only way to distinguish "scoring ran and produced nil"
    // from the VM's default state.
    let probe = EmbeddingProbe()
    Container.shared.contextualEmbedding.reset()
      .register {
        ContextualEmbedding(
          embedding: ProbingEmbeddable(assetsAvailable: true, probe: probe)
        )
      }
      .scope(.cached)

    let unsavedPodcastEpisode = UnsavedPodcastEpisode(
      unsavedPodcast: try Create.unsavedPodcast(title: "Cold Cache Podcast"),
      unsavedEpisode: try Create.unsavedEpisode(
        guid: "unsaved-cold",
        title: "Cold Cache Episode"
      )
    )
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(unsavedPodcastEpisode))

    viewModel.appear()

    try await Wait.until(
      { probe.vectorRequestCount() > 0 },
      {
        """
        Expected unsaved scoring to request at least one embedding vector. \
        vectorRequestCount: \(probe.vectorRequestCount())
        """
      }
    )
    for _ in 0..<30 { await Task.yield() }

    #expect(viewModel.displayedScore == nil)
  }

  @Test("unsaved episode skips vector scoring when embedding assets are unavailable")
  func unsavedEpisodeSkipsVectorScoringWhenEmbeddingAssetsUnavailable() async throws {
    let probe = EmbeddingProbe()
    Container.shared.contextualEmbedding.reset()
      .register {
        ContextualEmbedding(
          embedding: ProbingEmbeddable(assetsAvailable: false, probe: probe)
        )
      }
      .scope(.cached)

    let unsavedPodcastEpisode = UnsavedPodcastEpisode(
      unsavedPodcast: try Create.unsavedPodcast(title: "Unavailable Embedding Podcast"),
      unsavedEpisode: try Create.unsavedEpisode(
        guid: "unavailable-embedding",
        title: "Unavailable Embedding Episode"
      )
    )
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(unsavedPodcastEpisode))

    viewModel.appear()

    try await Wait.until(
      { probe.loadAssetsIfAvailableCount() > 0 },
      {
        """
        Expected unsaved scoring to check whether embedding assets are available.
        loadAssetsIfAvailableCount: \(probe.loadAssetsIfAvailableCount())
        """
      }
    )

    let observedVectorRequest: Bool
    do {
      try await Wait.until(
        maxAttempts: 100,
        delay: .milliseconds(10),
        priority: .userInitiated,
        { probe.vectorRequestCount() > 0 },
        { "no vector request observed within polling window" }
      )
      observedVectorRequest = true
    } catch {
      // Timeout is the success case — the unavailable-assets path stayed quiet.
      observedVectorRequest = false
    }

    #expect(observedVectorRequest == false)
    #expect(viewModel.displayedScore == nil)
  }

  @Test(
    "unsaved episode rescores once embedding assets become available on a later appear"
  )
  func unsavedEpisodeRescoresAfterAssetsBecomeAvailable() async throws {
    let (_, signalEpisodes) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Late Assets Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signalEpisodes)
    _ = try await RecommendationHelpers.startAndWaitForScores(for: signalEpisodes)

    // Embedding model starts mid-download: assets are not on disk, so the
    // unsaved scorer can only produce nil.
    let embeddable = MutableEmbeddable(assetsAvailable: false)
    Container.shared.contextualEmbedding.reset()
      .register { ContextualEmbedding(embedding: embeddable) }
      .scope(.cached)

    let unsavedPodcastEpisode = UnsavedPodcastEpisode(
      unsavedPodcast: try Create.unsavedPodcast(title: "Late Assets Podcast"),
      unsavedEpisode: try Create.unsavedEpisode(
        guid: "late-assets",
        title: "Late Assets Episode"
      )
    )
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(unsavedPodcastEpisode))

    viewModel.appear()
    try await RecommendationScoringTestHelpers.settleRecommendationEngine()

    // Precondition: the bootstrap pass ran but couldn't produce a score
    // with assets unavailable.
    #expect(viewModel.displayedScore == nil)

    // Embedding model finishes downloading on disk.
    embeddable.makeAssetsAvailable()

    // A later appear must re-score rather than re-applying the cached
    // no-score result — the prior nil was uncacheable, not the real score.
    viewModel.disappear()
    viewModel.appear()

    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in
        if case .similarity = viewModel.displayedScore { return true }
        return false
      },
      { @MainActor in
        """
        Re-appearing after embedding assets became available left the unsaved \
        episode stuck on the cached no-score result instead of re-scoring.
        score: \(String(describing: viewModel.displayedScore))
        """
      }
    )
  }

  @Test(
    "unsaved episode rescores in place once embedding assets become available without re-appearing"
  )
  func unsavedEpisodeRescoresInPlaceWhenAssetsBecomeAvailable() async throws {
    // Bind the mutable embeddable to the container before the engine starts so
    // its post-finish $scoringRevision observation captures this instance's
    // latch, not the test harness's default.
    let embeddable = MutableEmbeddable(assetsAvailable: false)
    Container.shared.contextualEmbedding.reset()
      .register { ContextualEmbedding(embedding: embeddable) }
      .scope(.cached)

    let (_, signalEpisodes) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "In-Place Late Assets Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signalEpisodes)
    _ = try await RecommendationHelpers.startAndWaitForScores(for: signalEpisodes)

    let unsavedPodcastEpisode = UnsavedPodcastEpisode(
      unsavedPodcast: try Create.unsavedPodcast(title: "In-Place Late Assets Podcast"),
      unsavedEpisode: try Create.unsavedEpisode(
        guid: "in-place-late-assets",
        title: "In-Place Late Assets Episode"
      )
    )
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(unsavedPodcastEpisode))

    viewModel.appear()
    try await RecommendationScoringTestHelpers.settleRecommendationEngine()

    // Precondition: the bootstrap pass ran but couldn't produce a score
    // with assets unavailable.
    #expect(viewModel.displayedScore == nil)

    // Assets land on disk and the embedding actor finishes its latch. The
    // coordinator's refreshOnAssetsLoaded observer awaits that latch and kicks
    // a fresh pass; the engine's $scoringRevision bump on the same latch is a
    // backstop. Either way the still-mounted detail view must rescore without
    // the user navigating away and back.
    embeddable.makeAssetsAvailable()
    await Container.shared.contextualEmbedding().loadAssetsIfAvailable()

    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in
        if case .similarity = viewModel.displayedScore { return true }
        return false
      },
      { @MainActor in
        """
        Embedding assets became available while the unsaved detail view was \
        still mounted but the score never recovered — the engine never bumped \
        $scoringRevision when the latch finished.
        score: \(String(describing: viewModel.displayedScore))
        """
      }
    )
  }

  @Test("unsaved episode hides the similarity score once the episode is rated")
  func unsavedEpisodeHidesScoreWhenRated() async throws {
    let (_, signalEpisodes) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Rated Guard Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signalEpisodes)
    _ = try await RecommendationHelpers.startAndWaitForScores(for: signalEpisodes)

    let ratedUnsaved = UnsavedPodcastEpisode(
      unsavedPodcast: try Create.unsavedPodcast(title: "Rated Guard Podcast"),
      unsavedEpisode: try Create.unsavedEpisode(
        guid: "unsaved-rated",
        title: "Already Rated Episode",
        rating: .liked,
        ratingDate: Date()
      )
    )
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(ratedUnsaved))

    viewModel.appear()
    try await RecommendationScoringTestHelpers.settleRecommendationEngine()

    #expect(viewModel.displayedScore == nil)
  }

  @Test("unsaved episode hides the similarity score once the episode is finished")
  func unsavedEpisodeHidesScoreWhenFinished() async throws {
    let (_, signalEpisodes) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Finished Guard Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signalEpisodes)
    _ = try await RecommendationHelpers.startAndWaitForScores(for: signalEpisodes)

    let finishedUnsaved = UnsavedPodcastEpisode(
      unsavedPodcast: try Create.unsavedPodcast(title: "Finished Guard Podcast"),
      unsavedEpisode: try Create.unsavedEpisode(
        guid: "unsaved-finished",
        title: "Already Finished Episode",
        finishDate: Date()
      )
    )
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(finishedUnsaved))

    viewModel.appear()
    try await RecommendationScoringTestHelpers.settleRecommendationEngine()

    #expect(viewModel.displayedScore == nil)
  }

  @Test("transitioning an unsaved episode to saved swaps the similarity score for a recommendation")
  func unsavedToSavedTransitionSwitchesToRecommendationScore() async throws {
    let (_, signalEpisodes) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Transition Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signalEpisodes)
    _ = try await RecommendationHelpers.startAndWaitForScores(for: signalEpisodes)

    let unsavedPodcastEpisode = UnsavedPodcastEpisode(
      unsavedPodcast: try Create.unsavedPodcast(title: "Transition Podcast"),
      unsavedEpisode: try Create.unsavedEpisode(
        guid: "unsaved-transition",
        title: "Will Be Saved"
      )
    )
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(unsavedPodcastEpisode))

    viewModel.appear()

    try await Wait.until(
      { @MainActor in
        if case .similarity = viewModel.displayedScore { return true }
        return false
      },
      { @MainActor in
        "Expected unsaved episode to show similarity score before save action."
      }
    )

    viewModel.addToTopOfQueue()

    // Once the unsaved → saved transition lands, the new `Episode` row has
    // no embedding yet. Embed it so the saved-side recommendation actually
    // resolves; without that step the engine correctly returns nil.
    try await Wait.until(
      { @MainActor in viewModel.episode.isSaved },
      { @MainActor in
        "Expected save to land before embedding the newly-saved episode. saved: \(viewModel.episode.isSaved)"
      }
    )
    let saved = try #require(
      try await repo.podcastEpisode(
        unsavedPodcastEpisode.mediaGUID,
        feedURL: unsavedPodcastEpisode.feedURL
      )
    )
    try await RecommendationHelpers.embedEpisodes([saved.episode])

    // Drive the engine's embedding-table observation through its 400ms
    // debounce so scoringRevision bumps and the saved-side fetch produces a
    // recommendation-kind score with the new embedding visible.
    _ = try await RecommendationHelpers.waitAdvancing {
      let isRecommendation = await MainActor.run {
        if case .recommendation = viewModel.displayedScore { return true }
        return false
      }
      return isRecommendation ? true : nil
    }
  }

  @Test("a saved-side fetch resolving after delete reverts state does not stale-write")
  func savedSideStaleWriteIsDiscardedAfterUnsavedTransition() async throws {
    let (_, signalEpisodes) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Stale Write Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signalEpisodes)

    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "Stale Write Target"),
        unsavedEpisode: try Create.unsavedEpisode(
          guid: "stale-write-target",
          title: "Stale Write Target"
        )
      )
    )
    try await RecommendationHelpers.embedEpisodes([podcastEpisode.episode])
    _ = try await RecommendationHelpers.startAndWaitForScores(for: [podcastEpisode.episode])

    // Arm the suspend hook before opening the view so the bootstrap fetch
    // parks inside `engine.recommendation(for:)` → `repo.episode(_:)`.
    let fakeRepo = repo as! FakeRepo
    fakeRepo.pendingEpisodeFetchSuspend(true)

    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(podcastEpisode))
    viewModel.appear()

    try await fakeRepo.waitForEpisodeFetchSuspended(count: 1)

    // Saved-side scoring is parked. Delete the podcast — observation flips
    // state to `.unsaved`; `transition(to:)` calls
    // `recommendationCoordinator.refresh()`, whose new snapshot
    // (`.unsaved`) differs from the parked task's (`.saved`), so the
    // coordinator cancels the parked task and kicks off a fresh
    // unsaved-side fetch.
    _ = try await repo.deletePodcast(podcastEpisode.podcast.id)

    // Wait for `.similarity` on the new `.unsaved` state — the correct
    // terminal. Anything that overwrites this after release is a stale
    // saved-side write.
    try await Wait.until(
      { @MainActor in
        guard !viewModel.episode.isSaved else { return false }
        if case .similarity = viewModel.displayedScore { return true }
        return false
      },
      { @MainActor in
        """
        Expected unsaved-side refresh task to land .similarity before releasing the held fetch.
        isSaved: \(viewModel.episode.isSaved)
        score: \(String(describing: viewModel.displayedScore))
        """
      }
    )

    // Release the parked saved-side fetch. Without the coordinator's
    // `Task.isCancelled` check and snapshot stale-drop in `runPass`, its
    // tail would overwrite `.similarity` with a stale `.recommendation`.
    await fakeRepo.resumeAllEpisodeFetchSuspensions()

    // Deterministic barrier — fires the instant the parked continuation
    // returns; the saved-side tail (score compute + MainActor hop into
    // `runPass`'s cancellation / snapshot gates) is then the only
    // outstanding work.
    try await fakeRepo.waitForEpisodeFetchCompleted(count: 1)
    // Drain the MainActor queue so the saved-side tail's gates run before
    // we assert.
    for _ in 0..<30 { await Task.yield() }

    #expect(viewModel.episode.isSaved == false)
    if case .recommendation = viewModel.displayedScore {
      Issue.record(
        """
        Stale .recommendation write landed after saved → unsaved transition; \
        the coordinator's cancellation / snapshot stale-drop in runPass regressed.
        """
      )
    }
    if case .similarity = viewModel.displayedScore {
      // Good — terminal state held.
    } else {
      Issue.record(
        """
        Expected stable .similarity post-release, got \
        \(String(describing: viewModel.displayedScore))
        """
      )
    }
  }
}

private struct EmbeddingProbe: Sendable {
  let loadAssetsIfAvailableCount = ThreadSafe<Int>(0)
  let vectorRequestCount = ThreadSafe<Int>(0)
}

// ContextualEmbedding is an actor and can't be subclassed, so the probe
// counts at the Embeddable boundary instead. `hasAvailableAssets` is
// touched on every loadAssetsIfAvailable() the actor hasn't already
// finished, and `embeddingResult(for:)` is touched on every vector(for:).
private struct ProbingEmbeddable: Embeddable {
  let assetsAvailable: Bool
  let probe: EmbeddingProbe
  let revision = 1

  var hasAvailableAssets: Bool {
    probe.loadAssetsIfAvailableCount { $0 += 1 }
    return assetsAvailable
  }

  func load() throws {}

  func requestAssets(completion: @escaping @Sendable ((any Error)?) -> Void) {
    completion(nil)
  }

  func embeddingResult(for string: String) throws -> any EmbeddableResult {
    probe.vectorRequestCount { $0 += 1 }
    return FakeEmbeddingResult(vectors: [[1, 0, 0]])
  }
}
