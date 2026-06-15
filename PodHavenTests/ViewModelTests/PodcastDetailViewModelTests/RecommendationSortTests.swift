// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("of PodcastDetailViewModel recommendation sort tests", .container)
@MainActor final class RecommendationSortTests {
  @DynamicInjected(\.repo) private var repo

  @Test(
    "recommendationScore sort option appears only once the scoring cache is warm, for both unsaved and saved podcasts"
  )
  func recommendationScoreSortHiddenUntilScoringCacheWarms() async throws {
    let unsavedSeries = UnsavedPodcastSeries(
      unsavedPodcast: try Create.unsavedPodcast(title: "Unsaved Preview"),
      unsavedEpisodes: [
        try Create.unsavedEpisode(guid: "a", title: "A"),
        try Create.unsavedEpisode(guid: "b", title: "B"),
      ]
    )
    let unsavedViewModel = PodcastDetailViewModel(unsavedPodcastSeries: unsavedSeries)

    let savedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(title: "Saved Detail"),
        unsavedEpisodes: [try Create.unsavedEpisode(guid: "x", title: "X")]
      )
    )
    let savedViewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(savedSeries.podcast))

    // Engine cold: the rec sort is hidden for both unsaved and saved podcasts.
    #expect(!unsavedViewModel.allSortMethods.contains(.recommendationScore))
    #expect(!savedViewModel.allSortMethods.contains(.recommendationScore))

    // Warming the engine flips the observable flag and reveals the option.
    let embeddable = ScriptedEmbeddable { text in
      if text.contains("Signal") { return [1, 0, 0] }
      return [0, 0, 1]
    }
    let (_, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      podcastDescription: "Signal",
      episodeDescriptions: ["Signal", "Signal", "Signal"],
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signals, embeddable: embeddable)
    _ = try await RecommendationHelpers.startAndWaitForScores(for: signals)

    #expect(unsavedViewModel.allSortMethods.contains(.recommendationScore))
    #expect(savedViewModel.allSortMethods.contains(.recommendationScore))
  }

  @Test("recommendationScore sort reorders episodes by score descending")
  func recommendationScoreSortReordersByScore() async throws {
    // Pin focused decone mode: exploratory strips three principal components
    // and on a fixture this small collapses score residuals to zero, which
    // would erase the ordering we're asserting.
    Container.shared.userSettings().$recommendationDeconeMode.new(.focused)

    // Engineered vectors give us a deterministic, monotonic similarity
    // gradient across candidates so the rec-score order is provably distinct
    // from newest-first. FakeEmbeddable derives vectors from String.hashValue,
    // which Swift re-seeds per process, so its candidate ordering was random
    // across CI runs and occasionally matched pubDate-descending.
    let embeddable = ScriptedEmbeddable { text in
      if text.contains("Filler") { return [0, 0, 1] }
      if text.contains("Signal") { return [1, 0, 0] }
      if text.contains("Target 0") { return [0.2, 0.98, 0] }
      if text.contains("Target 1") { return [0.4, 0.917, 0] }
      if text.contains("Target 2") { return [0.6, 0.8, 0] }
      if text.contains("Target 3") { return [0.8, 0.6, 0] }
      if text.contains("Target") { return [0, 1, 0] }
      return [0, 0, 1]
    }

    // Anchor the corpus mean off the signal/candidate cluster so mean-centering
    // preserves the engineered ordering. notInterested ratings keep these out
    // of both centroids and the candidate pool.
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

    // Descriptions carry the per-index discriminator the embeddable closure
    // matches on; titles share the constant "Target" branch so candidate
    // ordering comes entirely from descriptions.
    let (targetPodcast, candidateEpisodes) =
      try await RecommendationHelpers
      .createPodcastWithEpisodes(
        count: 4,
        podcastTitle: "Target",
        podcastDescription: "Target",
        episodeDescriptions: ["Target 0", "Target 1", "Target 2", "Target 3"]
      )
    try await RecommendationHelpers.embedEpisodes(candidateEpisodes, embeddable: embeddable)

    let scoreMap = try await RecommendationHelpers.startAndWaitForScores(
      for: candidateEpisodes
    )
    let expectedOrder =
      candidateEpisodes
      .sorted { lhs, rhs in
        let lhsScore = scoreMap[lhs.id]?.value ?? 0
        let rhsScore = scoreMap[rhs.id]?.value ?? 0
        if lhsScore != rhsScore { return lhsScore > rhsScore }
        if lhs.pubDate != rhs.pubDate { return lhs.pubDate > rhs.pubDate }
        if lhs.mediaGUID.guid != rhs.mediaGUID.guid {
          return lhs.mediaGUID.guid > rhs.mediaGUID.guid
        }
        return lhs.mediaGUID.mediaURL.rawValue.absoluteString
          > rhs.mediaGUID.mediaURL.rawValue.absoluteString
      }
      .map(\.id)
    // Engineered vectors make this guard hold by construction; keeping it
    // documents the contract and catches future fixture drift.
    let newestFirstOrder =
      candidateEpisodes
      .sorted { $0.pubDate > $1.pubDate }
      .map(\.id)
    try #require(
      expectedOrder != newestFirstOrder,
      "Rec-score order matched newestFirst; the test wouldn't prove the sort applied."
    )

    let viewModel = PodcastDetailViewModel(
      podcast: DisplayedPodcast(targetPodcast)
    )
    try await PodcastDetailTestHelpers.appear(viewModel)

    // The recommendation observation work can inherit the poller's priority;
    // keep this above `.background` so CI load does not starve the sort update.
    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in
        viewModel.saved
          && viewModel.episodeList.allEntries.count == candidateEpisodes.count
      },
      { @MainActor in
        """
        Expected target podcast to load all \(candidateEpisodes.count) episodes.
        saved: \(viewModel.saved)
        count: \(viewModel.episodeList.allEntries.count)
        """
      }
    )

    viewModel.currentSortMethod = .recommendationScore

    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in
        viewModel.episodeList.filteredEntries.compactMap(\.episodeID) == expectedOrder
      },
      { @MainActor in
        """
        Expected episodes sorted by recommendation score descending.
        Expected: \(expectedOrder)
        Actual: \(viewModel.episodeList.filteredEntries.compactMap(\.episodeID))
        """
      }
    )
  }

  @Test(
    "saved podcast: recommendationScore sort hides episodes without embeddings and re-shows them once an embedding lands"
  )
  func recommendationScoreSortHidesUnembeddedEpisodesInSavedPodcast() async throws {
    let embeddable = ScriptedEmbeddable { text in
      if text.contains("Filler") { return [0, 0, 1] }
      if text.contains("Signal") { return [1, 0, 0] }
      if text.contains("Target 0") { return [0.2, 0.98, 0] }
      if text.contains("Target 1") { return [0.4, 0.917, 0] }
      if text.contains("Target 2") { return [0.6, 0.8, 0] }
      if text.contains("Target") { return [0, 1, 0] }
      return [0, 0, 1]
    }
    try await primeEngine(with: embeddable)

    let (targetPodcast, targetEpisodes) =
      try await RecommendationHelpers
      .createPodcastWithEpisodes(
        count: 3,
        podcastTitle: "Target",
        podcastDescription: "Target",
        episodeDescriptions: ["Target 0", "Target 1", "Target 2"]
      )
    // Embed only the first two episodes; the third deliberately has no
    // EpisodeEmbedding row so the rec-score sort must hide it.
    let embeddedEpisodes = Array(targetEpisodes.prefix(2))
    let unembeddedEpisode = targetEpisodes[2]
    try await RecommendationHelpers.embedEpisodes(embeddedEpisodes, embeddable: embeddable)
    _ = try await RecommendationHelpers.startAndWaitForScores(for: embeddedEpisodes)

    let viewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(targetPodcast))
    try await PodcastDetailTestHelpers.appear(viewModel)

    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in
        viewModel.saved && viewModel.episodeList.allEntries.count == targetEpisodes.count
      },
      { @MainActor in
        """
        Expected the saved series to load all \(targetEpisodes.count) episodes.
        saved: \(viewModel.saved)
        count: \(viewModel.episodeList.allEntries.count)
        """
      }
    )

    viewModel.currentSortMethod = .recommendationScore

    let embeddedIDs = Set(embeddedEpisodes.map(\.id))
    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in
        Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)) == embeddedIDs
      },
      { @MainActor in
        """
        Expected rec-score sort to show only the two embedded episodes and \
        hide the unembedded one (\(unembeddedEpisode.id)).
        filteredEntries: \(viewModel.episodeList.filteredEntries.compactMap(\.episodeID))
        """
      }
    )

    // Embedding generation completes for the third episode: it must rejoin
    // the rec-sorted list without requiring a sort toggle or app restart.
    try await RecommendationHelpers.embedEpisodes([unembeddedEpisode], embeddable: embeddable)

    let allIDs = Set(targetEpisodes.map(\.id))
    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      {
        await MainActor.run {
          Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)) == allIDs
        }
      },
      { @MainActor in
        """
        Expected the newly-embedded episode \(unembeddedEpisode.id) to rejoin \
        the rec-sorted list once its embedding existed.
        filteredEntries: \(viewModel.episodeList.filteredEntries.compactMap(\.episodeID))
        """
      }
    )
  }

  @Test("recommendationScore sort orders unsaved-state episodes by similarity to liked centroid")
  func recommendationScoreSortOrdersUnsavedEpisodesBySimilarity() async throws {
    let embeddable = discoveryScriptedEmbeddable()
    try await primeEngine(with: embeddable)
    registerContainerEmbedding(embeddable)

    // Titles fall through to the [0,0,1] default and pubDates ascend with
    // index, so descriptions are the only discriminator and newest-first
    // disagrees with similarity-descending — the contract the #require below
    // pins.
    let unsavedSeries = UnsavedPodcastSeries(
      unsavedPodcast: try Create.unsavedPodcast(
        title: "Discovery",
        description: "Discovery"
      ),
      unsavedEpisodes: [
        try Create.unsavedEpisode(
          guid: "discovery-0",
          title: "Episode A",
          pubDate: Date(timeIntervalSince1970: 400),
          description: "Discovery 0"
        ),
        try Create.unsavedEpisode(
          guid: "discovery-1",
          title: "Episode B",
          pubDate: Date(timeIntervalSince1970: 300),
          description: "Discovery 1"
        ),
        try Create.unsavedEpisode(
          guid: "discovery-2",
          title: "Episode C",
          pubDate: Date(timeIntervalSince1970: 200),
          description: "Discovery 2"
        ),
        try Create.unsavedEpisode(
          guid: "discovery-3",
          title: "Episode D",
          pubDate: Date(timeIntervalSince1970: 100),
          description: "Discovery 3"
        ),
      ]
    )

    // Compute expected order via the same APIs the VM uses so the test
    // doesn't have to hand-derive whitening + rescaling values.
    let unsavedPodcastEpisodes = unsavedSeries.unsavedEpisodes.map { unsavedEpisode in
      UnsavedPodcastEpisode(
        unsavedPodcast: unsavedSeries.unsavedPodcast,
        unsavedEpisode: unsavedEpisode
      )
    }
    let scoresByMediaGUID = try await unsavedSimilarityScores(unsavedPodcastEpisodes)
    let expectedOrder =
      unsavedPodcastEpisodes
      .sorted { lhs, rhs in
        let lhsScore = scoresByMediaGUID[lhs.mediaGUID] ?? 0
        let rhsScore = scoresByMediaGUID[rhs.mediaGUID] ?? 0
        if lhsScore != rhsScore { return lhsScore > rhsScore }
        return lhs.unsavedEpisode.pubDate > rhs.unsavedEpisode.pubDate
      }
      .map(\.mediaGUID)
    let newestFirstOrder =
      unsavedPodcastEpisodes
      .sorted { $0.unsavedEpisode.pubDate > $1.unsavedEpisode.pubDate }
      .map(\.mediaGUID)
    try #require(
      expectedOrder != newestFirstOrder,
      "Similarity order matched newestFirst; the test wouldn't prove the sort applied."
    )

    let viewModel = PodcastDetailViewModel(unsavedPodcastSeries: unsavedSeries)
    try await PodcastDetailTestHelpers.appear(viewModel)

    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in viewModel.episodeList.allEntries.count == unsavedPodcastEpisodes.count },
      { @MainActor in
        """
        Expected unsaved series to surface all \(unsavedPodcastEpisodes.count) episodes.
        count: \(viewModel.episodeList.allEntries.count)
        """
      }
    )

    try await PodcastDetailTestHelpers.appear(viewModel)
    viewModel.currentSortMethod = .recommendationScore

    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in
        viewModel.episodeList.filteredEntries.map(\.mediaGUID) == expectedOrder
      },
      { @MainActor in
        """
        Expected unsaved episodes sorted by similarity score descending.
        Expected: \(expectedOrder)
        Actual: \(viewModel.episodeList.filteredEntries.map(\.mediaGUID))
        """
      }
    )
  }

  @Test("unsaved similarity pass exposes each row's score by mediaGUID")
  func unsavedSimilarityPassExposesRowScores() async throws {
    let embeddable = discoveryScriptedEmbeddable()
    try await primeEngine(with: embeddable)
    registerContainerEmbedding(embeddable)

    let unsavedSeries = UnsavedPodcastSeries(
      unsavedPodcast: try Create.unsavedPodcast(
        title: "Discovery",
        description: "Discovery"
      ),
      unsavedEpisodes: [
        try Create.unsavedEpisode(
          guid: "discovery-0",
          title: "Episode A",
          pubDate: Date(timeIntervalSince1970: 400),
          description: "Discovery 0"
        ),
        try Create.unsavedEpisode(
          guid: "discovery-1",
          title: "Episode B",
          pubDate: Date(timeIntervalSince1970: 300),
          description: "Discovery 1"
        ),
      ]
    )
    let unsavedPodcastEpisodes = unsavedSeries.unsavedEpisodes.map { unsavedEpisode in
      UnsavedPodcastEpisode(
        unsavedPodcast: unsavedSeries.unsavedPodcast,
        unsavedEpisode: unsavedEpisode
      )
    }
    let scoresByMediaGUID = try await unsavedSimilarityScores(unsavedPodcastEpisodes)
    try #require(scoresByMediaGUID.count == unsavedPodcastEpisodes.count)

    let viewModel = PodcastDetailViewModel(unsavedPodcastSeries: unsavedSeries)
    try await PodcastDetailTestHelpers.appear(viewModel)

    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in viewModel.episodeList.allEntries.count == unsavedPodcastEpisodes.count },
      { @MainActor in
        """
        Expected all unsaved episodes to surface before sorting.
        count: \(viewModel.episodeList.allEntries.count)
        """
      }
    )

    // No scoring pass has run under the default sort: nothing to expose yet.
    #expect(viewModel.similarityScoreByMediaGUID.isEmpty)

    viewModel.currentSortMethod = .recommendationScore

    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in
        unsavedPodcastEpisodes.allSatisfy {
          viewModel.similarityScoreByMediaGUID[$0.mediaGUID] != nil
        }
      },
      { @MainActor in
        """
        Expected the similarity pass to expose a score for every row.
        scores: \(unsavedPodcastEpisodes.map { viewModel.similarityScoreByMediaGUID[$0.mediaGUID] })
        """
      }
    )
    for episode in unsavedPodcastEpisodes {
      #expect(
        viewModel.similarityScoreByMediaGUID[episode.mediaGUID]
          == scoresByMediaGUID[episode.mediaGUID]
      )
    }
    #expect(viewModel.similarityScoreByMediaGUID.count == unsavedPodcastEpisodes.count)
  }

  @Test(
    "unsaved series rescores by similarity once embedding assets become available on a later appear"
  )
  func unsavedSeriesRescoresAfterAssetsBecomeAvailable() async throws {
    let scripted = discoveryScriptedEmbeddable()
    try await primeEngine(with: scripted)

    // Embedding model starts mid-download: the unsaved scorer can only
    // produce an empty score map.
    let embeddable = MutableEmbeddable(
      assetsAvailable: false,
      vectorFor: scripted.vectorFor
    )
    Container.shared.contextualEmbedding.reset()
      .register { ContextualEmbedding(embedding: embeddable) }
      .scope(.cached)

    let unsavedSeries = UnsavedPodcastSeries(
      unsavedPodcast: try Create.unsavedPodcast(
        title: "Discovery",
        description: "Discovery"
      ),
      unsavedEpisodes: [
        try Create.unsavedEpisode(
          guid: "discovery-0",
          title: "Episode A",
          pubDate: Date(timeIntervalSince1970: 400),
          description: "Discovery 0"
        ),
        try Create.unsavedEpisode(
          guid: "discovery-1",
          title: "Episode B",
          pubDate: Date(timeIntervalSince1970: 300),
          description: "Discovery 1"
        ),
        try Create.unsavedEpisode(
          guid: "discovery-2",
          title: "Episode C",
          pubDate: Date(timeIntervalSince1970: 200),
          description: "Discovery 2"
        ),
        try Create.unsavedEpisode(
          guid: "discovery-3",
          title: "Episode D",
          pubDate: Date(timeIntervalSince1970: 100),
          description: "Discovery 3"
        ),
      ]
    )
    let unsavedPodcastEpisodes = unsavedSeries.unsavedEpisodes.map { unsavedEpisode in
      UnsavedPodcastEpisode(
        unsavedPodcast: unsavedSeries.unsavedPodcast,
        unsavedEpisode: unsavedEpisode
      )
    }

    let viewModel = PodcastDetailViewModel(unsavedPodcastSeries: unsavedSeries)
    try await PodcastDetailTestHelpers.appear(viewModel)

    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in viewModel.episodeList.allEntries.count == unsavedPodcastEpisodes.count },
      { @MainActor in
        """
        Expected all unsaved episodes to surface before sorting.
        count: \(viewModel.episodeList.allEntries.count)
        """
      }
    )

    viewModel.currentSortMethod = .recommendationScore

    // Precondition: the assets-unavailable scoring pass settled. With an
    // empty score map the comparator collapses to pubDate order, which on
    // these fixtures matches the newest-first default — distinguishability
    // comes from the recovery assertion's similarity order instead.
    try await RecommendationScoringTestHelpers.settleRecommendationEngine()

    // Embedding model finishes downloading on disk.
    embeddable.makeAssetsAvailable()

    // Expected similarity order, computed via the same APIs the VM uses,
    // now that assets are loadable.
    let scoresByMediaGUID = try await unsavedSimilarityScores(unsavedPodcastEpisodes)
    let expectedOrder =
      unsavedPodcastEpisodes
      .sorted { lhs, rhs in
        let lhsScore = scoresByMediaGUID[lhs.mediaGUID] ?? 0
        let rhsScore = scoresByMediaGUID[rhs.mediaGUID] ?? 0
        if lhsScore != rhsScore { return lhsScore > rhsScore }
        return lhs.unsavedEpisode.pubDate > rhs.unsavedEpisode.pubDate
      }
      .map(\.mediaGUID)
    let newestFirstOrder =
      unsavedPodcastEpisodes
      .sorted { $0.unsavedEpisode.pubDate > $1.unsavedEpisode.pubDate }
      .map(\.mediaGUID)
    try #require(
      expectedOrder != newestFirstOrder,
      "Similarity order matched pubDate order; the test wouldn't prove a re-score ran."
    )

    // A later appear must re-score rather than re-applying the cached
    // empty score map — the prior empty map was uncacheable.
    viewModel.disappear()
    try await PodcastDetailTestHelpers.appear(viewModel)

    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in
        viewModel.episodeList.filteredEntries.map(\.mediaGUID) == expectedOrder
      },
      { @MainActor in
        """
        Re-appearing after embedding assets became available left the unsaved \
        series stuck on the cached empty score map instead of re-scoring.
        Expected: \(expectedOrder)
        Actual: \(viewModel.episodeList.filteredEntries.map(\.mediaGUID))
        """
      }
    )
  }

  @Test(
    "unsaved series: switching sorts replaces the recommendationScore comparator each direction"
  )
  func unsavedSeriesSortRoundTripsThroughRecommendationScore() async throws {
    let unsavedSeries = UnsavedPodcastSeries(
      unsavedPodcast: try Create.unsavedPodcast(title: "Round Trip"),
      unsavedEpisodes: [
        try Create.unsavedEpisode(
          guid: "a",
          title: "Older",
          pubDate: Date(timeIntervalSince1970: 100)
        ),
        try Create.unsavedEpisode(
          guid: "b",
          title: "Middle",
          pubDate: Date(timeIntervalSince1970: 200)
        ),
        try Create.unsavedEpisode(
          guid: "c",
          title: "Newer",
          pubDate: Date(timeIntervalSince1970: 300)
        ),
      ]
    )
    let viewModel = PodcastDetailViewModel(unsavedPodcastSeries: unsavedSeries)
    try await PodcastDetailTestHelpers.appear(viewModel)

    try await Wait.until(
      { @MainActor in
        viewModel.episodeList.filteredEntries.map(\.title) == ["Newer", "Middle", "Older"]
      },
      { @MainActor in
        """
        Expected default newest-first order for the unsaved series.
        titles: \(viewModel.episodeList.filteredEntries.map(\.title))
        """
      }
    )

    try await PodcastDetailTestHelpers.appear(viewModel)

    // No signal corpus means the engine cache stays cold and similarity
    // scoring returns nil for every row; the comparator should still fall
    // back to pubDate-descending so the user sees a stable, non-empty list.
    viewModel.currentSortMethod = .recommendationScore
    try await Wait.until(
      { @MainActor in
        viewModel.episodeList.filteredEntries.map(\.title) == ["Newer", "Middle", "Older"]
      },
      { @MainActor in
        """
        Expected recommendationScore with cold cache to fall back to pubDate-desc.
        titles: \(viewModel.episodeList.filteredEntries.map(\.title))
        """
      }
    )

    viewModel.currentSortMethod = .oldestFirst
    try await Wait.until(
      { @MainActor in
        viewModel.episodeList.filteredEntries.map(\.title) == ["Older", "Middle", "Newer"]
      },
      { @MainActor in
        """
        Expected oldestFirst to replace the recommendationScore comparator.
        titles: \(viewModel.episodeList.filteredEntries.map(\.title))
        """
      }
    )

    viewModel.currentSortMethod = .recommendationScore
    try await Wait.until(
      { @MainActor in
        viewModel.episodeList.filteredEntries.map(\.title) == ["Newer", "Middle", "Older"]
      },
      { @MainActor in
        """
        Expected recommendationScore to re-install after another sort took over.
        titles: \(viewModel.episodeList.filteredEntries.map(\.title))
        """
      }
    )
  }

  @Test(
    "subscribing while recommendationScore is active preserves the sort selection and the episode set across the unsaved→saved transition"
  )
  func subscribingPreservesRecommendationSortAcrossUnsavedToSavedTransition() async throws {
    let embeddable = discoveryScriptedEmbeddable()
    try await primeEngine(with: embeddable)
    registerContainerEmbedding(embeddable)

    let unsavedSeries = UnsavedPodcastSeries(
      unsavedPodcast: try Create.unsavedPodcast(
        title: "Discovery",
        description: "Discovery"
      ),
      unsavedEpisodes: [
        try Create.unsavedEpisode(
          guid: "discovery-0",
          title: "Episode A",
          pubDate: Date(timeIntervalSince1970: 400),
          description: "Discovery 0"
        ),
        try Create.unsavedEpisode(
          guid: "discovery-1",
          title: "Episode B",
          pubDate: Date(timeIntervalSince1970: 300),
          description: "Discovery 1"
        ),
        try Create.unsavedEpisode(
          guid: "discovery-2",
          title: "Episode C",
          pubDate: Date(timeIntervalSince1970: 200),
          description: "Discovery 2"
        ),
        try Create.unsavedEpisode(
          guid: "discovery-3",
          title: "Episode D",
          pubDate: Date(timeIntervalSince1970: 100),
          description: "Discovery 3"
        ),
      ]
    )

    let unsavedPodcastEpisodes = unsavedSeries.unsavedEpisodes.map { unsavedEpisode in
      UnsavedPodcastEpisode(
        unsavedPodcast: unsavedSeries.unsavedPodcast,
        unsavedEpisode: unsavedEpisode
      )
    }
    let originalMediaGUIDs = Set(unsavedPodcastEpisodes.map(\.mediaGUID))
    let scoresByMediaGUID = try await unsavedSimilarityScores(unsavedPodcastEpisodes)
    let unsavedExpectedOrder =
      unsavedPodcastEpisodes
      .sorted { lhs, rhs in
        let lhsScore = scoresByMediaGUID[lhs.mediaGUID] ?? 0
        let rhsScore = scoresByMediaGUID[rhs.mediaGUID] ?? 0
        if lhsScore != rhsScore { return lhsScore > rhsScore }
        return lhs.unsavedEpisode.pubDate > rhs.unsavedEpisode.pubDate
      }
      .map(\.mediaGUID)

    let viewModel = PodcastDetailViewModel(unsavedPodcastSeries: unsavedSeries)
    try await PodcastDetailTestHelpers.appear(viewModel)

    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in viewModel.episodeList.allEntries.count == unsavedPodcastEpisodes.count },
      { @MainActor in "Expected all unsaved episodes to surface before subscribe." }
    )

    viewModel.currentSortMethod = .recommendationScore

    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in
        viewModel.episodeList.filteredEntries.map(\.mediaGUID) == unsavedExpectedOrder
      },
      { @MainActor in
        """
        Expected unsaved similarity sort to apply before subscribe.
        Expected: \(unsavedExpectedOrder)
        Actual: \(viewModel.episodeList.filteredEntries.map(\.mediaGUID))
        """
      }
    )

    viewModel.subscribe()

    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in viewModel.saved },
      { @MainActor in "Expected VM to transition to .saved after subscribe()." }
    )

    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in
        Set(viewModel.episodeList.allEntries.map(\.mediaGUID)) == originalMediaGUIDs
      },
      { @MainActor in
        """
        Expected the persisted episode set to match the unsaved seed by MediaGUID.
        Expected: \(originalMediaGUIDs)
        Actual: \(Set(viewModel.episodeList.allEntries.map(\.mediaGUID)))
        """
      }
    )

    // Sort selection survives the transition; the persisted-side scoring path
    // takes over for subsequent scoringRevision ticks.
    #expect(viewModel.currentSortMethod == .recommendationScore)
  }

  // MARK: - Recommendation Sort Helpers

  // Engineered embeddable for the "Discovery" candidate fixtures: each
  // description maps to a vector with a monotonically increasing first
  // component, while the bare "Discovery" branch backs the podcast vector.
  private func discoveryScriptedEmbeddable() -> ScriptedEmbeddable {
    ScriptedEmbeddable { text in
      if text.contains("Filler") { return [0, 0, 1] }
      if text.contains("Signal") { return [1, 0, 0] }
      if text.contains("Discovery 0") { return [0.2, 0.98, 0] }
      if text.contains("Discovery 1") { return [0.4, 0.917, 0] }
      if text.contains("Discovery 2") { return [0.6, 0.8, 0] }
      if text.contains("Discovery 3") { return [0.8, 0.6, 0] }
      if text.contains("Discovery") { return [0, 1, 0] }
      return [0, 0, 1]
    }
  }

  // Pins focused decone, plants the filler corpus + signal centroid, and
  // waits for the engine cache to be hot. Decone is pinned because
  // exploratory mode strips three principal components and collapses
  // residuals on these small fixtures.
  private func primeEngine(with embeddable: ScriptedEmbeddable) async throws {
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

  // Bind the same engineered embeddable into the container so the VM's
  // unsaved scorer reads vectors from the same coordinate system the
  // engine used to build its centroid.
  private func registerContainerEmbedding(_ embeddable: ScriptedEmbeddable) {
    Container.shared.contextualEmbedding.reset()
      .register { ContextualEmbedding(embedding: embeddable) }
      .scope(.cached)
  }

  private func unsavedSimilarityScores(
    _ unsavedPodcastEpisodes: [UnsavedPodcastEpisode]
  ) async throws -> [MediaGUID: Float] {
    let contextualEmbedding = Container.shared.contextualEmbedding()
    await contextualEmbedding.loadAssetsIfAvailable()
    let engine = Container.shared.recommendationEngine()
    var orderedGUIDs = [MediaGUID](capacity: unsavedPodcastEpisodes.count)
    var vectors = [[Float]](capacity: unsavedPodcastEpisodes.count)
    for unsavedPodcastEpisode in unsavedPodcastEpisodes {
      let podcastVector = try await EmbeddingService.podcastContextVector(
        for: unsavedPodcastEpisode.unsavedPodcast,
        embedding: contextualEmbedding
      )
      let vector = try await EmbeddingService.episodeEmbeddingVector(
        for: unsavedPodcastEpisode.unsavedEpisode,
        podcastVector: podcastVector,
        embedding: contextualEmbedding
      )
      orderedGUIDs.append(unsavedPodcastEpisode.mediaGUID)
      vectors.append(vector)
    }
    let similarities = try await engine.similarityScores(forEmbeddings: vectors)
    var scores = [MediaGUID: Float](capacity: unsavedPodcastEpisodes.count)
    for (mediaGUID, similarity) in zip(orderedGUIDs, similarities) {
      guard let similarity else { continue }
      scores[mediaGUID] = similarity
    }
    return scores
  }
}
