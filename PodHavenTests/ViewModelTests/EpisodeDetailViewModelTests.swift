// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of EpisodeDetailViewModel tests", .container)
@MainActor final class EpisodeDetailViewModelTests {
  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.appDB) private var appDB
  @DynamicInjected(\.navigation) private var navigation
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.repo) private var repo

  private var fakeQueue: FakeQueue { queue as! FakeQueue }

  @Test("performAppear loads a saved episode and observes finish updates")
  func performAppearLoadsSavedEpisodeAndObservesFinishUpdates() async throws {
    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "Episode Detail"),
        unsavedEpisode: try Create.unsavedEpisode(
          guid: "episode-detail",
          title: "Episode Detail",
          currentTime: CMTime.seconds(123)
        )
      )
    )
    let viewModel = EpisodeDetailViewModel(
      episode: DisplayedEpisode(try podcastEpisode.toOriginalUnsavedPodcastEpisode())
    )

    try await viewModel.performAppear()

    #expect(viewModel.episode.isSaved)
    #expect(viewModel.episode.episodeID == podcastEpisode.id)

    _ = try await repo.markFinished(podcastEpisode.id)

    try await Wait.until(
      { @MainActor in
        viewModel.episode.finished && viewModel.episode.currentTime == .zero
      },
      { @MainActor in
        """
        Expected performAppear observation to pick up finish changes.
        finished: \(viewModel.episode.finished)
        currentTime: \(viewModel.episode.currentTime)
        """
      }
    )
  }

  @Test("listed episodes expose a share URL before detail hydration")
  func listedEpisodesExposeShareURLBeforeDetailHydration() async throws {
    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "List Episode Detail"),
        unsavedEpisode: try Create.unsavedEpisode(
          guid: "list-episode-detail",
          title: "List Episode Detail"
        )
      )
    )
    let listableEpisodes =
      try await observatory.listablePodcastEpisodes(
        filter: Episode.Columns.id == podcastEpisode.id
      )
      .get()
    let listedEpisode = try #require(listableEpisodes.first)

    let viewModel = EpisodeDetailViewModel(listedEpisode: ListedEpisode(listedEpisode))

    #expect(
      ShareURL.episode(feedURL: viewModel.episode.feedURL, guid: viewModel.episode.mediaGUID.guid)
        == ShareURL.episode(feedURL: podcastEpisode.feedURL, guid: podcastEpisode.mediaGUID.guid)
    )

    try await viewModel.performAppear()

    #expect(viewModel.episode.episodeID == podcastEpisode.id)
  }

  @Test("missing saved listed episodes alert and dismiss instead of fabricating unsaved detail")
  func missingSavedListedEpisodesAlertAndDismiss() async throws {
    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "Deleted Episode"),
        unsavedEpisode: try Create.unsavedEpisode(
          guid: "deleted-episode-detail",
          title: "Deleted Episode"
        )
      )
    )
    let listableEpisodes =
      try await observatory.listablePodcastEpisodes(
        filter: Episode.Columns.id == podcastEpisode.id
      )
      .get()
    let listedEpisode = try #require(listableEpisodes.first)
    let listed = ListedEpisode(listedEpisode)

    navigation.currentTab = .episodes
    navigation.episodes.path = [.episodesViewType(.recentEpisodes), .listedEpisode(listed)]

    _ = try await repo.deletePodcast(podcastEpisode.podcast.id)

    let viewModel = EpisodeDetailViewModel(listedEpisode: listed)

    try await viewModel.performAppear()

    #expect(alert.config != nil)
    #expect(navigation.episodes.path == [.episodesViewType(.recentEpisodes)])
  }

  @Test("missing listed unsaved episodes revert to unsaved detail without dismissing")
  func missingListedUnsavedEpisodesRevertToUnsavedDetail() async throws {
    let unsavedPodcastEpisode = UnsavedPodcastEpisode(
      unsavedPodcast: try Create.unsavedPodcast(title: "Unsaved Podcast"),
      unsavedEpisode: try Create.unsavedEpisode(
        guid: "listed-unsaved",
        title: "Unsaved Detail",
        description: "Unsaved Description"
      )
    )
    let listed = ListedEpisode(unsavedPodcastEpisode)
    let viewModel = EpisodeDetailViewModel(listedEpisode: listed)

    try await viewModel.performAppear()

    #expect(viewModel.episode.isSaved == false)
    #expect(viewModel.episode.title == unsavedPodcastEpisode.title)
    #expect(viewModel.episode.description == unsavedPodcastEpisode.description)
    #expect(alert.config == nil)
  }

  @Test("missing unsaved displayed episodes stay on their unsaved detail")
  func missingUnsavedDisplayedEpisodesStayUnsaved() async throws {
    let unsavedPodcastEpisode = UnsavedPodcastEpisode(
      unsavedPodcast: try Create.unsavedPodcast(title: "Displayed Unsaved Podcast"),
      unsavedEpisode: try Create.unsavedEpisode(
        guid: "displayed-unsaved",
        title: "Displayed Unsaved Detail",
        description: "Displayed Unsaved Description"
      )
    )
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(unsavedPodcastEpisode))

    try await viewModel.performAppear()

    #expect(viewModel.episode.isSaved == false)
    #expect(viewModel.episode.title == unsavedPodcastEpisode.title)
    #expect(viewModel.episode.description == unsavedPodcastEpisode.description)
    #expect(alert.config == nil)
  }

  @Test("observed deleted saved episodes revert to unsaved detail")
  func observedDeletedSavedEpisodesRevertToUnsavedDetail() async throws {
    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "Observed Delete"),
        unsavedEpisode: try Create.unsavedEpisode(
          guid: "observed-delete",
          title: "Observed Delete"
        )
      )
    )
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(podcastEpisode))

    try await viewModel.performAppear()
    _ = try await repo.deletePodcast(podcastEpisode.podcast.id)

    try await Wait.until(
      { @MainActor in
        viewModel.episode.isSaved == false
          && viewModel.episode.mediaGUID == podcastEpisode.mediaGUID
      },
      { @MainActor in
        """
        Expected deleted saved episode to revert to unsaved detail.
        saved: \(viewModel.episode.isSaved)
        episode: \(viewModel.episode.toString)
        """
      }
    )
  }

  @Test("tag observation rebinds after saved episode is deleted and re-saved")
  func tagObservationRebindsAfterDeleteAndResave() async throws {
    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "Tag Delete Resave"),
        unsavedEpisode: try Create.unsavedEpisode(
          guid: "tag-delete-resave",
          title: "Tag Delete Resave"
        )
      )
    )
    let tag = try await repo.insertTag(UnsavedTag(name: "Recovered"))
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(podcastEpisode))

    try await viewModel.performAppear()
    _ = try await repo.deletePodcast(podcastEpisode.podcast.id)

    try await Wait.until(
      { @MainActor in !viewModel.episode.isSaved },
      { @MainActor in
        "Expected deleted saved episode to revert before re-saving. episode: \(viewModel.episode.toString)"
      }
    )

    viewModel.markFinished()

    try await Wait.until(
      { @MainActor in viewModel.episode.isSaved && viewModel.episode.finished },
      { @MainActor in
        """
        Expected markFinished to re-save the episode.
        saved: \(viewModel.episode.isSaved)
        finished: \(viewModel.episode.finished)
        """
      }
    )

    let resaved = try #require(try await repo.podcastEpisode(podcastEpisode.episode.mediaGUID))
    try await repo.addTag(tag.id, to: resaved.id)

    try await Wait.until(
      { @MainActor in viewModel.tags.map(\.id) == [tag.id] },
      { @MainActor in
        """
        Expected tag observation to rebind to the re-saved episode and surface the added tag.
        tags: \(viewModel.tags.map(\.name))
        """
      }
    )
  }

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

    try await viewModel.performAppear()

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
    let resaved = try #require(try await repo.podcastEpisode(podcastEpisode.episode.mediaGUID))
    try await RecommendationHelpers.embedEpisodes([resaved.episode])

    // Drive the engine's embedding-table observation through its 1s
    // debounce so contextRevision bumps and the saved-side fetch re-runs
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

    try await viewModel.performAppear()

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

    try await viewModel.performAppear()

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
    #expect(try await repo.podcastEpisode(unsavedPodcastEpisode.mediaGUID) == nil)
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

    try await viewModel.performAppear()

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

    try await viewModel.performAppear()

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

    try await viewModel.performAppear()

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

    try await viewModel.performAppear()

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

    try await viewModel.performAppear()

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
    let saved = try #require(try await repo.podcastEpisode(unsavedPodcastEpisode.mediaGUID))
    try await RecommendationHelpers.embedEpisodes([saved.episode])

    // Drive the engine's embedding-table observation through its 1s
    // debounce so contextRevision bumps and the saved-side fetch produces a
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
    try await viewModel.performAppear()

    try await fakeRepo.waitForEpisodeFetchSuspended(count: 1)

    // Saved-side scoring is parked. Delete the podcast — observation flips
    // state to `.unsaved` and the kind-change refresh runs a fresh fetch.
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

    // Release the parked saved-side fetch. Without the kind guard, its tail
    // overwrites `.similarity` with a stale `.recommendation`.
    await fakeRepo.resumeAllEpisodeFetchSuspensions()

    // Deterministic barrier — fires the instant the parked continuation
    // returns; the saved-side tail (score compute + MainActor hop into the
    // kind guard) is then the only outstanding work.
    try await fakeRepo.waitForEpisodeFetchCompleted(count: 1)
    // Drain the MainActor queue so the saved-side tail's guard/write runs
    // before we assert.
    for _ in 0..<30 { await Task.yield() }

    #expect(viewModel.episode.isSaved == false)
    if case .recommendation = viewModel.displayedScore {
      Issue.record(
        """
        Stale .recommendation write landed after saved → unsaved transition; \
        the state-kind guard in fetchRecommendation regressed.
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

  @Test("observation restarts after a podcastEpisodeWithTags failure")
  func observationRestartsAfterPodcastEpisodeWithTagsFailure() async throws {
    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "Recovery"),
        unsavedEpisode: try Create.unsavedEpisode(guid: "recovery", title: "Recovery")
      )
    )
    let tag = try await repo.insertTag(UnsavedTag(name: "Recovered"))
    try await repo.addTag(tag.id, to: podcastEpisode.id)

    let fakeObservatory = try #require(observatory as? FakeObservatory)
    let dbReader = appDB.db
    fakeObservatory.podcastEpisodeWithTagsScript([
      { _ in
        ValueObservation
          .tracking { _ -> PodcastEpisodeWithTags? in
            throw TestError.simulatedFailure
          }
          .values(in: dbReader)
      }
    ])

    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(podcastEpisode))

    // First performAppear subscribes to the scripted (failing) observation.
    // SwiftUI can deliver multiple .onAppear without an intervening
    // .onDisappear, so simulate that by re-entering performAppear from the
    // poll loop. With the fix, the failed task self-clears and the next
    // restart subscribes to the real observatory and surfaces the tag.
    // Without the fix, observationTask permanently retains the dead task
    // and every subsequent startObservation() returns early.
    try await viewModel.performAppear()

    // Raise priority above the default `.background` so the unstructured
    // `Task {}` that `startObservation()` spawns from inside this poll
    // block doesn't inherit `.background` and get starved long enough
    // that every subsequent rebind short-circuits on the still-running
    // failed task.
    try await Wait.until(
      maxAttempts: 200,
      delay: .milliseconds(50),
      priority: .userInitiated,
      { @MainActor in
        try await viewModel.performAppear()
        return viewModel.tags.map(\.id) == [tag.id]
      },
      { @MainActor in
        """
        Expected observation to restart after failure and surface the tag.
        tags: \(viewModel.tags.map(\.name))
        """
      }
    )
  }

  @Test("addToTopOfQueue is a no-op for the first queued episode")
  func addToTopOfQueueIsNoOpForFirstQueuedEpisode() async throws {
    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "Queue Guard"),
        unsavedEpisode: try Create.unsavedEpisode(
          guid: "queue-guard",
          title: "Queue Guard",
          queueOrder: 0,
          queueDate: Date()
        )
      )
    )
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(podcastEpisode))

    viewModel.addToTopOfQueue()

    try fakeQueue.expectNoCall(methodName: "unshift")
    #expect(viewModel.atTopOfQueue == true)
  }

  @Test("addTag observes saved episode tags and removeTag clears them")
  func addAndRemoveTagOnSavedEpisode() async throws {
    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "Tagged"),
        unsavedEpisode: try Create.unsavedEpisode(guid: "tagged-ep", title: "Tagged")
      )
    )
    let tag = try await repo.insertTag(UnsavedTag(name: "Bookmark"))
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(podcastEpisode))

    try await viewModel.performAppear()

    viewModel.addTag(tag.id)

    try await Wait.until(
      { @MainActor in viewModel.tags.map(\.id) == [tag.id] },
      { @MainActor in
        "Expected episode tag observation to surface added tag. tags: \(viewModel.tags.map(\.name))"
      }
    )

    viewModel.removeTag(tag.id)

    try await Wait.until(
      { @MainActor in viewModel.tags.isEmpty },
      { @MainActor in
        "Expected episode tag observation to clear after removeTag. tags: \(viewModel.tags.map(\.name))"
      }
    )
  }

  @Test("addTag writes tag mapping for a saved listed episode before performAppear hydrates")
  func addTagWritesMappingForSavedListedEpisodeBeforePerformAppear() async throws {
    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "Pre-Hydration Tag"),
        unsavedEpisode: try Create.unsavedEpisode(
          guid: "pre-hydration-tag",
          title: "Pre-Hydration Tag"
        )
      )
    )
    let listableEpisodes =
      try await observatory.listablePodcastEpisodes(
        filter: Episode.Columns.id == podcastEpisode.id
      )
      .get()
    let listedEpisode = try #require(listableEpisodes.first)
    let tag = try await repo.insertTag(UnsavedTag(name: "Bookmark"))
    let viewModel = EpisodeDetailViewModel(listedEpisode: ListedEpisode(listedEpisode))

    // The view shows TagsView based on viewModel.episode.isSaved, which is
    // already true from the listed snapshot — before performAppear() finishes
    // hydrating podcastEpisode. A tap landing in that window must still write
    // the tag mapping; otherwise it is silently dropped.
    #expect(viewModel.episode.isSaved)

    viewModel.addTag(tag.id)

    try await Wait.until(
      { @MainActor in
        let observed = try await self.observatory.podcastEpisodeWithTags(podcastEpisode.id).get()
        return observed?.tags.map(\.id) == [tag.id]
      },
      { @MainActor in
        "Expected addTag to write the tag mapping before performAppear hydration."
      }
    )
  }

  @Test("addTag is a no-op for unsaved episodes")
  func addTagIsNoOpForUnsavedEpisode() async throws {
    let unsavedPodcastEpisode = UnsavedPodcastEpisode(
      unsavedPodcast: try Create.unsavedPodcast(title: "Unsaved For Tagging"),
      unsavedEpisode: try Create.unsavedEpisode(
        guid: "unsaved-tagging",
        title: "Unsaved For Tagging"
      )
    )
    let tag = try await repo.insertTag(UnsavedTag(name: "Listen Later"))
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(unsavedPodcastEpisode))

    viewModel.addTag(tag.id)

    #expect(viewModel.episode.isSaved == false)
    #expect(viewModel.tags.isEmpty)
    #expect(try await repo.podcastEpisode(unsavedPodcastEpisode.mediaGUID) == nil)
  }

  @Test("markFinished saves an unsaved episode before finishing it")
  func markFinishedSavesUnsavedEpisodeBeforeFinishingIt() async throws {
    let unsavedPodcastEpisode = UnsavedPodcastEpisode(
      unsavedPodcast: try Create.unsavedPodcast(title: "Unsaved Podcast"),
      unsavedEpisode: try Create.unsavedEpisode(
        guid: "unsaved-finish",
        title: "Unsaved Episode",
        currentTime: CMTime.seconds(42)
      )
    )
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(unsavedPodcastEpisode))

    viewModel.markFinished()

    try await Wait.until(
      { @MainActor in
        viewModel.episode.isSaved && viewModel.episode.finished
      },
      { @MainActor in
        """
        Expected markFinished to save and finish the unsaved episode.
        saved: \(viewModel.episode.isSaved)
        finished: \(viewModel.episode.finished)
        """
      }
    )

    let savedEpisode = try await repo.podcastEpisode(unsavedPodcastEpisode.unsavedEpisode.id)
    #expect(savedEpisode != nil)
    #expect(savedEpisode?.episode.finishDate != nil)
    #expect(savedEpisode?.episode.currentTime == .zero)
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
