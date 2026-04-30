// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import IdentifiedCollections
import Testing

@testable import PodHaven

@Suite("RecommendationEngine tests", .container)
class RecommendationEngineTests {
  @DynamicInjected(\.recommendationEngine) private var engine
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.sharedState) private var sharedState

  // MARK: - Helpers

  private func createPodcastWithEpisodes(
    count: Int,
    podcastTitle: String = String.random(),
    podcastDescription: String = String.random(),
    episodeDescriptions: [String]? = nil,
    ratings: [EpisodeRating?]? = nil,
    finished: [Bool]? = nil,
    pubDateOffset: (Int) -> TimeInterval = { i in TimeInterval(-i * 86400) }
  ) async throws -> (podcast: Podcast, episodes: [Episode]) {
    let unsavedPodcast = try Create.unsavedPodcast(
      title: podcastTitle,
      description: podcastDescription
    )

    let unsavedEpisodes = try (0..<count)
      .map { i in
        try buildUnsaved(
          index: i,
          podcastTitle: podcastTitle,
          episodeDescriptions: episodeDescriptions,
          ratings: ratings,
          finished: finished,
          pubDateOffset: pubDateOffset
        )
      }
    let entries = unsavedEpisodes.map {
      UnsavedPodcastEpisode(unsavedPodcast: unsavedPodcast, unsavedEpisode: $0)
    }

    let podcastEpisodes = try await repo.upsertPodcastEpisodes(entries)
    let podcast = try #require(podcastEpisodes.first?.podcast)
    return (podcast, podcastEpisodes.map(\.episode))
  }

  // Adds new episodes to an existing podcast — useful for testing podcast-level
  // behavior (affinity, candidate filtering) where signals and candidates need
  // to share a podcast row.
  private func addEpisodes(
    to podcast: Podcast,
    count: Int,
    episodeDescriptions: [String]? = nil,
    ratings: [EpisodeRating?]? = nil,
    finished: [Bool]? = nil,
    pubDateOffset: (Int) -> TimeInterval = { i in TimeInterval(-i * 86400) }
  ) async throws -> [Episode] {
    let unsavedPodcast = try Create.unsavedPodcast(
      feedURL: podcast.feedURL,
      title: podcast.title,
      image: podcast.image,
      description: podcast.description
    )

    let unsavedEpisodes = try (0..<count)
      .map { i in
        try buildUnsaved(
          index: i,
          podcastTitle: podcast.title,
          episodeDescriptions: episodeDescriptions,
          ratings: ratings,
          finished: finished,
          pubDateOffset: pubDateOffset
        )
      }
    let entries = unsavedEpisodes.map {
      UnsavedPodcastEpisode(unsavedPodcast: unsavedPodcast, unsavedEpisode: $0)
    }

    let podcastEpisodes = try await repo.upsertPodcastEpisodes(entries)
    return podcastEpisodes.map(\.episode)
  }

  private func buildUnsaved(
    index i: Int,
    podcastTitle: String,
    episodeDescriptions: [String]?,
    ratings: [EpisodeRating?]?,
    finished: [Bool]?,
    pubDateOffset: (Int) -> TimeInterval
  ) throws -> UnsavedEpisode {
    let rating = ratings?[safe: i] ?? nil
    let isFinished = finished?[safe: i] ?? false
    let description = episodeDescriptions?[safe: i] ?? "Episode \(i) description"
    return try Create.unsavedEpisode(
      title: "Episode \(i) of \(podcastTitle)",
      pubDate: Date().addingTimeInterval(pubDateOffset(i)),
      duration: CMTime(seconds: 1800, preferredTimescale: 1),
      description: description,
      finishDate: isFinished ? Date() : nil,
      rating: rating,
      ratingDate: rating != nil ? Date() : nil
    )
  }

  private func embedEpisodes(
    _ episodes: [Episode],
    embeddable: any Embeddable = FakeEmbeddable()
  ) async throws {
    let embedding = ContextualEmbedding(embedding: embeddable)
    embedding.requestAndLoadAssetsIfNeeded()
    try await EmbeddingService.upsertEpisodeEmbeddings(
      for: episodes,
      embedding: embedding
    )
  }

  // The engine spawns its observation Task on `start()` and only populates
  // its cache once the Observatory has emitted. Tests for "expected
  // non-empty" results poll until the cache lands; tests for "expected
  // empty" results don't need to wait since both cold and hot states yield
  // empty. (Helpers stash the engine in a local before the polling closure
  // so the @Sendable boundary doesn't capture the non-Sendable test class.)
  private func startAndWaitForRecs() async throws -> IdentifiedArrayOf<RecommendedEpisode> {
    engine.start()
    let engine = self.engine
    return try await waitAdvancing {
      let recs = try await engine.topRecommendations()
      return recs.isEmpty ? nil : recs
    }
  }

  private func startAndWaitForScores(
    for episodes: [Episode]
  ) async throws -> [Episode.ID: RecommendationScore] {
    engine.start()
    let engine = self.engine
    return try await waitAdvancing {
      let map = try await engine.recommendations(for: episodes)
      return map.isEmpty ? nil : map
    }
  }

  // The engine batches cache rebuilds through a 1s Debounce. New triggers
  // can land at any time during the test, each cancelling the prior sleep
  // and arming a fresh one (FakeSleeper requires manual advance). Polling
  // with a per-iteration advance fires whatever sleep is currently armed
  // and cleanly handles the case where another rebuild gets scheduled
  // after a previous one already fired.
  private func waitAdvancing<T: Sendable>(
    _ block: @Sendable @escaping () async throws -> T?
  ) async throws -> T {
    let sleeper = Container.shared.sleeper() as! FakeSleeper
    return try await Wait.forValue {
      await sleeper.advanceTime(by: .seconds(1))
      return try await block()
    }
  }

  // MARK: - Minimum Threshold

  @Test("returns empty when fewer than 3 signal episodes")
  func minimumThreshold() async throws {
    let (_, episodes) = try await createPodcastWithEpisodes(
      count: 2,
      ratings: [.loved, .liked]
    )
    try await embedEpisodes(episodes)

    engine.start()
    let recommendations = try await engine.topRecommendations()
    #expect(recommendations.isEmpty)
  }

  // MARK: - Basic Recommendations

  @Test("returns recommendations when threshold is met")
  func basicRecommendations() async throws {
    // Create rated episodes (signal)
    let (_, signalEpisodes) = try await createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal Podcast",
      ratings: [.loved, .liked, .liked]
    )
    try await embedEpisodes(signalEpisodes)

    // Create candidate episodes (unrated, unfinished, unqueued)
    let (_, candidateEpisodes) = try await createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Candidate Podcast"
    )
    try await embedEpisodes(candidateEpisodes)

    let recommendations = try await startAndWaitForRecs()
    #expect(!recommendations.isEmpty)
    #expect(recommendations.count <= 10)

    // Verify deterministic ordering (scores should be descending)
    for i in 0..<(recommendations.count - 1) {
      #expect(recommendations[i].score.value >= recommendations[i + 1].score.value)
    }
  }

  // MARK: - Candidate Filtering

  @Test("excludes finished episodes from candidates")
  func excludesFinished() async throws {
    let (_, signalEpisodes) = try await createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await embedEpisodes(signalEpisodes)

    let (_, candidates) = try await createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Candidates",
      finished: [true, false]
    )
    try await embedEpisodes(candidates)

    let recommendations = try await startAndWaitForRecs()
    let recommendedIDs = Set(recommendations.map(\.episode.id))

    #expect(!recommendedIDs.contains(candidates[0].id))
  }

  @Test("excludes rated episodes from candidates")
  func excludesRated() async throws {
    let (_, signalEpisodes) = try await createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await embedEpisodes(signalEpisodes)

    let (_, rated) = try await createPodcastWithEpisodes(
      count: 1,
      podcastTitle: "Rated Candidate",
      ratings: [.disliked]
    )
    try await embedEpisodes(rated)

    // Only candidate is rated, so the candidate pool is empty and recs
    // come back empty either way — no point waiting on the cache.
    engine.start()
    let recommendations = try await engine.topRecommendations()
    let recommendedIDs = Set(recommendations.map(\.episode.id))
    #expect(!recommendedIDs.contains(rated[0].id))
  }

  // MARK: - All Disliked

  @Test("handles all-disliked history gracefully")
  func allDisliked() async throws {
    _ = try await createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Disliked",
      ratings: [.disliked, .disliked, .disliked]
    )

    let (_, candidates) = try await createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Candidates"
    )
    try await embedEpisodes(candidates)

    // Should return empty since there's no positive centroid
    engine.start()
    let recommendations = try await engine.topRecommendations()
    #expect(recommendations.isEmpty)
  }

  // MARK: - Reasons

  @Test("recommendations include reasons")
  func recommendationsHaveReasons() async throws {
    let (_, signalEpisodes) = try await createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await embedEpisodes(signalEpisodes)

    let (_, candidates) = try await createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Candidates"
    )
    try await embedEpisodes(candidates)

    let recommendations = try await startAndWaitForRecs()
    for rec in recommendations {
      #expect(!rec.score.reasons.isEmpty)
    }
  }

  // MARK: - New reasons semantics

  @Test("year-old episodes don't include recentlyPublished reason")
  func oldEpisodesExcludeFreshnessReason() async throws {
    let (_, signals) = try await createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await embedEpisodes(signals)

    // Default cadence is weekly (7d plateau + 7d half-life). At 365d the
    // episode is far past the plateau, so `.recentlyPublished` (gated by
    // `freshness.inPlateau`) should not fire. Use the unfiltered scoring API
    // since the multiplier (~0.019) drops the gated score below the top
    // API's confidence floor.
    let (_, old) = try await createPodcastWithEpisodes(
      count: 1,
      podcastTitle: "Archive",
      pubDateOffset: { _ in TimeInterval(-365 * 86400) }
    )
    try await embedEpisodes(old)

    let scores = try await startAndWaitForScores(for: old)
    let oldEpisode = try #require(old.first)
    let oldScore = try #require(scores[oldEpisode.id])
    #expect(!oldScore.reasons.contains(.recentlyPublished))
  }

  @Test("candidates from an unknown podcast don't include podcastAffinity reason")
  func unknownPodcastExcludesAffinityReason() async throws {
    let (_, signals) = try await createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await embedEpisodes(signals)

    // Candidates live in a podcast with zero positive signals — affinity
    // settles at the neutral 0.5 prior, which must not clear the reason filter.
    let (_, candidates) = try await createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Unknown"
    )
    try await embedEpisodes(candidates)

    let recs = try await startAndWaitForRecs()
    for rec in recs where candidates.map(\.id).contains(rec.episode.id) {
      #expect(!rec.score.reasons.contains(.podcastAffinity))
    }
  }

  @Test("semantically opposite candidates don't include similarToLiked reason")
  func oppositeCandidatesExcludeSimilarityReason() async throws {
    // Engineer vectors so the similarity feature drops well below 0.5 for
    // candidates whose embeddings point the opposite direction from signals.
    let embeddable = ScriptedEmbeddable { text in
      if text.contains("Loved") { return [1, 0, 0] }
      if text.contains("Opposite") { return [-1, 0, 0] }
      return [0, 0, 1]  // neutral filler for podcast descriptions etc.
    }

    let (_, signals) = try await createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Loved Show",
      podcastDescription: "neutral",
      episodeDescriptions: ["Loved Desc 0", "Loved Desc 1", "Loved Desc 2"],
      ratings: [.loved, .loved, .loved]
    )
    try await embedEpisodes(signals, embeddable: embeddable)

    let (_, opposites) = try await createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Opposite Show",
      podcastDescription: "neutral",
      episodeDescriptions: ["Opposite Desc 0", "Opposite Desc 1"]
    )
    try await embedEpisodes(opposites, embeddable: embeddable)

    let recs = try await startAndWaitForRecs()
    let oppositeIDs = Set(opposites.map(\.id))
    let oppositeRecs = recs.filter { oppositeIDs.contains($0.episode.id) }
    #expect(!oppositeRecs.isEmpty)
    for rec in oppositeRecs {
      #expect(!rec.score.reasons.contains(.similarToLiked))
    }
  }

  @Test("candidates from a loved podcast include podcastAffinity reason")
  func lovedPodcastIncludesAffinityReason() async throws {
    // Three loved episodes on the same podcast drive affinity above neutral.
    let (lovedPodcast, signals) = try await createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Loved",
      ratings: [.loved, .loved, .loved]
    )
    try await embedEpisodes(signals)

    // Unrated episodes on the SAME podcast are candidates that should carry
    // the affinity reason.
    let candidates = try await addEpisodes(to: lovedPodcast, count: 2)
    try await embedEpisodes(candidates)

    let recs = try await startAndWaitForRecs()
    let candidateIDs = Set(candidates.map(\.id))
    let candidateRecs = recs.filter { candidateIDs.contains($0.episode.id) }
    #expect(!candidateRecs.isEmpty)
    for rec in candidateRecs {
      #expect(rec.score.reasons.contains(.podcastAffinity))
    }
  }

  // MARK: - Arbitrary-list scoring

  @Test("recommendations(for:) scores every requested episode")
  func recommendationsForArbitraryList() async throws {
    let (_, signals) = try await createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await embedEpisodes(signals)

    let (_, episodes) = try await createPodcastWithEpisodes(
      count: 4,
      podcastTitle: "Arbitrary"
    )
    try await embedEpisodes(episodes)

    let map = try await startAndWaitForScores(for: episodes)
    #expect(map.count == episodes.count)
    for episode in episodes {
      #expect(map[episode.id] != nil)
    }
  }

  @Test("recommendations(for:) returns empty when signal threshold isn't met")
  func recommendationsForArbitraryListBelowThreshold() async throws {
    let (_, signals) = try await createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Signal",
      ratings: [.loved, .liked]
    )
    try await embedEpisodes(signals)

    let (_, episodes) = try await createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Arbitrary"
    )
    try await embedEpisodes(episodes)

    engine.start()
    let map = try await engine.recommendations(for: episodes)
    #expect(map.isEmpty)
  }

  @Test("recommendations(for:) scores rated and finished episodes the top API skips")
  func recommendationsForArbitraryListIncludesFilteredEpisodes() async throws {
    // Enough positive signals from a separate podcast to satisfy the threshold.
    let (_, signals) = try await createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await embedEpisodes(signals)

    // Mixed bag: a disliked episode and a finished episode — both would be
    // excluded by `topRecommendations` via the candidate filter.
    let (_, filtered) = try await createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Filtered",
      ratings: [.disliked, nil],
      finished: [false, true]
    )
    try await embedEpisodes(filtered)

    let map = try await startAndWaitForScores(for: filtered)
    #expect(map.count == filtered.count)
    for episode in filtered {
      #expect(map[episode.id] != nil)
    }

    // Sanity-check: the same episodes are absent from the top API.
    let top = try await engine.topRecommendations()
    let topIDs = Set(top.map(\.episode.id))
    for episode in filtered {
      #expect(!topIDs.contains(episode.id))
    }
  }

  // MARK: - Tie-breaking

  @Test("breaks score ties by newer pubDate first")
  func tieBreakByPubDate() async throws {
    // Deterministic embeddings so similarity is identical for both candidates.
    let embeddable = ScriptedEmbeddable { _ in [1, 0, 0] }

    let (_, signals) = try await createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await embedEpisodes(signals, embeddable: embeddable)

    // Two candidates on the same podcast, same embedding. pubDates placed in
    // the future so freshnessScore short-circuits to 1.0 exactly for both
    // (daysSince <= 0 guard) — that's the only way to get bit-exact freshness
    // equality across two distinct pubDates. Same podcast → identical affinity.
    // Same embedding → identical similarity. Score tie by construction.
    let (_, candidates) = try await createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Candidates",
      pubDateOffset: { i in TimeInterval((i == 0 ? 2 : 1) * 86400) }
    )
    try await embedEpisodes(candidates, embeddable: embeddable)

    let recs = try await startAndWaitForRecs()
    let candidateIDs = Set(candidates.map(\.id))
    let candidateRecs = recs.filter { candidateIDs.contains($0.episode.id) }
    #expect(candidateRecs.count == 2)
    let first = try #require(candidateRecs.first)
    let second = try #require(candidateRecs.last)
    #expect(first.score.value == second.score.value)
    #expect(first.episode.pubDate > second.episode.pubDate)
  }

  // MARK: - Limit

  @Test("honors custom limit by truncating results")
  func customLimit() async throws {
    let (_, signals) = try await createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await embedEpisodes(signals)

    let (_, candidates) = try await createPodcastWithEpisodes(
      count: 5,
      podcastTitle: "Candidates"
    )
    try await embedEpisodes(candidates)

    engine.start()
    let engine = self.engine
    let limited = try await waitAdvancing {
      let recs = try await engine.topRecommendations(limit: 3)
      return recs.count == 3 ? recs : nil
    }
    #expect(limited.count == 3)
  }

  // MARK: - onDeck exclusion

  @Test("excludes onDeck episode from candidates")
  func excludesOnDeck() async throws {
    let (_, signals) = try await createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await embedEpisodes(signals)

    let (candidatePodcast, candidates) = try await createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Candidates"
    )
    try await embedEpisodes(candidates)

    let onDeckEpisode = try #require(candidates.first)
    sharedState.$onDeck.new(
      OnDeck(from: PodcastEpisode(podcast: candidatePodcast, episode: onDeckEpisode))
    )

    let recs = try await startAndWaitForRecs()
    let recommendedIDs = Set(recs.map(\.episode.id))
    #expect(!recommendedIDs.contains(onDeckEpisode.id))
  }

  // MARK: - Partial-listen signals

  @Test("partial-listen signals contribute alongside ratings")
  func partialSignalsContribute() async throws {
    let (_, ratedEpisodes) = try await createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Rated",
      ratings: [.loved, .liked]
    )
    try await embedEpisodes(ratedEpisodes)

    let (_, playedEpisodes) = try await createPodcastWithEpisodes(
      count: 1,
      podcastTitle: "Played"
    )
    try await embedEpisodes(playedEpisodes)
    let played = try #require(playedEpisodes.first)
    try await repo.updatePlayback(
      played.id,
      currentTime: CMTime.seconds(900),
      playedFrom: CMTime.seconds(0),
      now: Date()
    )

    let (_, candidates) = try await createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Candidates"
    )
    try await embedEpisodes(candidates)

    let recs = try await startAndWaitForRecs()
    #expect(!recs.isEmpty)
  }

  @Test("partial signals lift podcast affinity for the played show")
  func partialSignalsLiftAffinity() async throws {
    let (playedPodcast, ratedEpisodes) = try await createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "BaselineRatings",
      ratings: [.loved, .liked]
    )
    try await embedEpisodes(ratedEpisodes)

    let played = try await addEpisodes(to: playedPodcast, count: 1)
    try await embedEpisodes(played)
    let playedID = try #require(played.first?.id)
    try await repo.updatePlayback(
      playedID,
      currentTime: CMTime.seconds(1700),
      playedFrom: CMTime.seconds(0),
      now: Date()
    )

    let candidates = try await addEpisodes(to: playedPodcast, count: 1)
    try await embedEpisodes(candidates)

    let recs = try await startAndWaitForRecs()
    let candidateRec = try #require(recs.first { $0.episode.id == candidates[0].id })
    #expect(candidateRec.score.reasons.contains(.podcastAffinity))
  }

  @Test("onDeck transition rebuilds the cache against fresh partial signals")
  func onDeckTransitionRebuildsCache() async throws {
    let (_, ratedEpisodes) = try await createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Rated",
      ratings: [.loved, .liked]
    )
    try await embedEpisodes(ratedEpisodes)

    let (_, candidates) = try await createPodcastWithEpisodes(
      count: 1,
      podcastTitle: "Candidate"
    )
    try await embedEpisodes(candidates)

    // Start the engine before any partial exists — initial cache lacks
    // the third signal, so the rating-only count is below threshold.
    engine.start()

    let (_, played) = try await createPodcastWithEpisodes(
      count: 1,
      podcastTitle: "Played"
    )
    try await embedEpisodes(played)
    let playedEpisode = try #require(played.first)
    try await repo.updatePlayback(
      playedEpisode.id,
      currentTime: CMTime.seconds(1500),
      playedFrom: CMTime.seconds(0),
      now: Date()
    )

    // No GRDB observation fires for the bitmap write. An onDeck id
    // transition is what propagates the partial signal into the cache.
    let onDeckEpisode = try #require(try await repo.podcastEpisode(playedEpisode.id))
    sharedState.$onDeck.new(OnDeck(from: onDeckEpisode))
    sharedState.$onDeck.new(nil)

    let engine = self.engine
    let recs = try await waitAdvancing {
      let recs = try await engine.topRecommendations()
      return recs.isEmpty ? nil : recs
    }
    #expect(!recs.isEmpty)
  }

  @Test("a started-but-no-bitmap episode is NOT a signal (legacy / pre-v40)")
  func startedWithoutBitmapNotSignal() async throws {
    let (_, signals) = try await createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await embedEpisodes(signals)

    let (_, started) = try await createPodcastWithEpisodes(
      count: 1,
      podcastTitle: "Legacy"
    )
    let legacyID = try #require(started.first?.id)
    try await repo.updateCurrentTime(legacyID, currentTime: CMTime.seconds(60))

    let partials = try await repo.allUnratedListenedEpisodes()
    #expect(partials.contains { $0.id == legacyID } == false)
  }

  // MARK: - Signals without embeddings

  @Test("returns empty when signals exist but none have embeddings yet")
  func signalsWithoutEmbeddings() async throws {
    // 3 rated signals but no embeddings yet — transient state during initial
    // embedding-pipeline warmup. hasAnyEmbeddings is true (from candidates) so
    // the early hasAnyEmbeddings gate passes, but buildCentroids returns nil
    // because no signal embedding is available to seed the positive centroid.
    _ = try await createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )

    let (_, candidates) = try await createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Candidates"
    )
    try await embedEpisodes(candidates)

    engine.start()
    let recs = try await engine.topRecommendations()
    #expect(recs.isEmpty)
  }

  // MARK: - Empty input

  @Test("recommendations(for:) with empty input returns empty without touching the cache")
  func recommendationsForEmptyInput() async throws {
    let map = try await engine.recommendations(for: [])
    #expect(map.isEmpty)
  }

  // MARK: - Per-podcast freshness cadence

  @Test("evergreen cadence preserves old episode scores against the weekly default")
  func evergreenCadencePreservesOldEpisodeScore() async throws {
    // Same embedding + same podcast title across candidates so similarity and
    // affinity are identical; the only thing varying between the two
    // candidates is the freshness cadence on their podcast row. Evergreen
    // multiplier is always 1.0; weekly at 365d ≈ 0.019 (after the 7d
    // plateau + 7d half-life). Use the unfiltered scoring API since the
    // weekly candidate's gated score falls below the top API's confidence
    // floor.
    let embeddable = ScriptedEmbeddable { _ in [1, 0, 0] }

    let (_, signals) = try await createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await embedEpisodes(signals, embeddable: embeddable)

    let oldOffset: (Int) -> TimeInterval = { _ in TimeInterval(-365 * 86400) }

    let (_, weeklyCandidates) = try await createPodcastWithEpisodes(
      count: 1,
      podcastTitle: "Weekly Default",
      pubDateOffset: oldOffset
    )
    try await embedEpisodes(weeklyCandidates, embeddable: embeddable)

    let (evergreenPodcast, evergreenCandidates) = try await createPodcastWithEpisodes(
      count: 1,
      podcastTitle: "Evergreen Cadence",
      pubDateOffset: oldOffset
    )
    try await embedEpisodes(evergreenCandidates, embeddable: embeddable)
    _ = try await repo.updateFreshnessCadence(evergreenPodcast.id, freshnessCadence: .evergreen)

    let scores = try await startAndWaitForScores(for: weeklyCandidates + evergreenCandidates)
    let weeklyEpisode = try #require(weeklyCandidates.first)
    let evergreenEpisode = try #require(evergreenCandidates.first)
    let weeklyScore = try #require(scores[weeklyEpisode.id])
    let evergreenScore = try #require(scores[evergreenEpisode.id])

    // Evergreen × 1.0 dominates weekly × ~0.019 by orders of magnitude.
    #expect(evergreenScore.value > weeklyScore.value * 10)
    // Evergreen never surfaces .recentlyPublished — the user has opted out
    // of freshness signal — and weekly at this age is below the threshold.
    #expect(!evergreenScore.reasons.contains(.recentlyPublished))
    #expect(!weeklyScore.reasons.contains(.recentlyPublished))
  }

  @Test("monthly cadence retains older episode scores better than weekly")
  func monthlyCadenceOutpacesWeekly() async throws {
    let embeddable = ScriptedEmbeddable { _ in [1, 0, 0] }

    let (_, signals) = try await createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await embedEpisodes(signals, embeddable: embeddable)

    // 60 days old: weekly gives multiplier = 1/(1 + 53/7) ≈ 0.117; monthly's
    // plateau (30d) + 30d half-life gives 1/(1 + 30/30) = 0.5.
    let oldOffset: (Int) -> TimeInterval = { _ in TimeInterval(-60 * 86400) }

    let (_, weeklyCandidates) = try await createPodcastWithEpisodes(
      count: 1,
      podcastTitle: "Weekly",
      pubDateOffset: oldOffset
    )
    try await embedEpisodes(weeklyCandidates, embeddable: embeddable)

    let (monthlyPodcast, monthlyCandidates) = try await createPodcastWithEpisodes(
      count: 1,
      podcastTitle: "Monthly",
      pubDateOffset: oldOffset
    )
    try await embedEpisodes(monthlyCandidates, embeddable: embeddable)
    _ = try await repo.updateFreshnessCadence(monthlyPodcast.id, freshnessCadence: .monthly)

    let scores = try await startAndWaitForScores(for: weeklyCandidates + monthlyCandidates)
    let weeklyEpisode = try #require(weeklyCandidates.first)
    let monthlyEpisode = try #require(monthlyCandidates.first)
    let weeklyScore = try #require(scores[weeklyEpisode.id])
    let monthlyScore = try #require(scores[monthlyEpisode.id])

    #expect(monthlyScore.value > weeklyScore.value)
  }

  @Test("plateau keeps within-cadence episodes at full freshness")
  func plateauPreservesWithinCadenceEpisodes() async throws {
    let embeddable = ScriptedEmbeddable { _ in [1, 0, 0] }

    let (_, signals) = try await createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await embedEpisodes(signals, embeddable: embeddable)

    // 6 days old on a weekly podcast → still inside the plateau, so
    // multiplier = 1.0 and the score equals the same-base evergreen score
    // for the same age. Older test using a 365d offset confirms the curve
    // *does* decay past the plateau.
    let withinCadenceOffset: (Int) -> TimeInterval = { _ in TimeInterval(-6 * 86400) }

    let (_, weeklyCandidates) = try await createPodcastWithEpisodes(
      count: 1,
      podcastTitle: "Weekly Plateau",
      pubDateOffset: withinCadenceOffset
    )
    try await embedEpisodes(weeklyCandidates, embeddable: embeddable)

    let (evergreenPodcast, evergreenCandidates) = try await createPodcastWithEpisodes(
      count: 1,
      podcastTitle: "Evergreen Plateau",
      pubDateOffset: withinCadenceOffset
    )
    try await embedEpisodes(evergreenCandidates, embeddable: embeddable)
    _ = try await repo.updateFreshnessCadence(evergreenPodcast.id, freshnessCadence: .evergreen)

    let scores = try await startAndWaitForScores(for: weeklyCandidates + evergreenCandidates)
    let weeklyEpisode = try #require(weeklyCandidates.first)
    let evergreenEpisode = try #require(evergreenCandidates.first)
    let weeklyScore = try #require(scores[weeklyEpisode.id])
    let evergreenScore = try #require(scores[evergreenEpisode.id])

    #expect(weeklyScore.value == evergreenScore.value)
    #expect(weeklyScore.reasons.contains(.recentlyPublished))
  }

  @Test("recently-published reason fires for fresh non-evergreen episodes")
  func recentlyPublishedFiresForFreshEpisodes() async throws {
    let (_, signals) = try await createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await embedEpisodes(signals)

    // 1 day old on a weekly cadence → inside the 7d plateau, so
    // `freshness.inPlateau` is true and `.recentlyPublished` fires.
    let (_, fresh) = try await createPodcastWithEpisodes(
      count: 1,
      podcastTitle: "Fresh",
      pubDateOffset: { _ in TimeInterval(-1 * 86400) }
    )
    try await embedEpisodes(fresh)

    let recs = try await startAndWaitForRecs()
    let freshRec = try #require(recs.first { $0.episode.id == fresh.first?.id })
    #expect(freshRec.score.reasons.contains(.recentlyPublished))
  }

  @Test("recently-published reason is suppressed for evergreen podcasts even when fresh")
  func recentlyPublishedSuppressedForEvergreen() async throws {
    let (_, signals) = try await createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await embedEpisodes(signals)

    // Freshly published episode but on an evergreen podcast — multiplier is
    // 1.0 so the score is fine, but the reason should not surface.
    let (evergreenPodcast, candidates) = try await createPodcastWithEpisodes(
      count: 1,
      podcastTitle: "Evergreen",
      pubDateOffset: { _ in TimeInterval(-1 * 86400) }
    )
    try await embedEpisodes(candidates)
    _ = try await repo.updateFreshnessCadence(evergreenPodcast.id, freshnessCadence: .evergreen)

    let recs = try await startAndWaitForRecs()
    let candidateRec = try #require(recs.first { $0.episode.id == candidates.first?.id })
    #expect(!candidateRec.score.reasons.contains(.recentlyPublished))
  }
}

// MARK: - Array Safe Subscript

extension Array {
  fileprivate subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
