// Copyright Justin Bishop, 2026

import AVFoundation
import Accelerate
import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging

// MARK: - Types

// The "new info" a recommendation adds to an episode: a blended score in
// [0, 1] and the reasons that fired above their neutral midpoint. Returned
// on its own by `recommendations(for:)` so callers that already have the
// episodes don't get them echoed back.
struct RecommendationScore: Sendable {
  let value: Float
  let reasons: [RecommendationReason]

  // Stretch the [0.5, max] segment onto [0.5, 1.0] so the top observed
  // candidate displays as 100% while preserving "below 50% = below baseline."
  // The neutral midpoint stays at 50% so a UI threshold like "show 'For You'
  // when score >= 50%" keeps its meaning across rebuilds; only above-baseline
  // scores get re-anchored against the latest pool. Pass-through when `max`
  // doesn't beat the baseline (degenerate cold-start corpus).
  func rescaledForDisplay(max: Float) -> RecommendationScore {
    guard value > 0.5, max > 0.5 else { return self }
    let stretched = (value - 0.5) * 0.5 / (max - 0.5)
    return RecommendationScore(
      value: Swift.min(1.0, 0.5 + stretched),
      reasons: reasons
    )
  }
}

// `topRecommendations` publishes ranked IDs paired with their scores;
// callers hydrate display rows separately so cache/save state stays fresh
// without a re-rank.
typealias RankedRecommendation = (id: Episode.ID, score: RecommendationScore)

enum RecommendationReason: Hashable, Sendable {
  case similarToLiked
  case podcastAffinity
  case recentlyPublished
}

// MARK: - Container

extension Container {
  var recommendationEngine: Factory<RecommendationEngine> {
    Factory(self) { RecommendationEngine() }.scope(.cached)
  }
}

// MARK: - RecommendationEngine

struct RecommendationEngine: Sendable {
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.recommendationRepo) private var recommendationRepo
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.sleeper) private var sleeper
  @DynamicInjected(\.taskPriority) private var taskPriority

  private static let log = Log.as(LogSubsystem.Recommendations.engine)

  private static let minimumDataThreshold = 3
  private static let minimumScoreThreshold: Float = 0.1

  // Must sum to 1.0. Similarity dominates so a single liked episode
  // doesn't drag in everything that podcast ever published. Freshness isn't
  // a summand — it's a multiplicative gate (see `scoreCandidate`).
  private static let similarityWeight: Float = 0.9
  private static let podcastAffinityWeight: Float = 0.1

  // Centroid weights
  private static let lovedWeight: Float = 1.0
  private static let likedWeight: Float = 0.6
  private static let partialWeight: Float = 0.5

  // Bayesian smoothing prior for podcast affinity
  private static let affinityPrior: Float = 2.0

  // Podcast affinity — dislikes contribute but at less strength.
  private static let dislikedAffinityWeight: Float = 0.4

  // Temporal decay half-life in days
  private static let decayHalfLifeDays: Double = 180

  // MARK: - Cached Scoring Context

  private let cache = ThreadSafe<ScoringContext?>(nil)
  private let cacheDebounce = Debounce(duration: .seconds(1))
  private let recommendationsDebounce = Debounce(duration: .milliseconds(400))
  private let startOnce = Once()

  // Display-rescaling anchor: max raw score from the most recent
  // `topRecommendations` rebuild, which scans the full candidate pool.
  // `recommendations(for:)` reads it but never writes — an arbitrary subset
  // would set an artificially low max and inflate every other surface.
  // Stays at 1.0 until the first rebuild so cold-start callers see un-rescaled
  // scores instead of a misleading 100% on whatever lands first.
  private let observedMaxScore = ThreadSafe<Float>(1.0)

  // Whitening mean is recomputed only when one of these signals fires; in
  // steady state cache rebuilds reuse the cached vector and skip the full
  // 188 MB scan. Counts that stay inside [shrink, growth] map to drift well
  // below 1% in display-rounded scores (see whiteningMean cache logic).
  private static let whiteningCountGrowthMax: Float = 1.25
  private static let whiteningCountShrinkMin: Float = 0.8

  // Cached whitening mean keyed on (model revision, recipe version, count).
  // Revision changes mean the vectors live in a different space; recipe
  // version changes mean every vector got re-written in place; count moving
  // outside [shrink, growth] means the corpus turned over enough to matter.
  // Anything else (new ratings, partial-listen ticks, routine feed adds)
  // leaves the cached mean valid.
  private let cachedWhiteningMean = ThreadSafe<
    (mean: [Float], revision: Int, recipeVersion: Int, count: Int)?
  >(nil)

  // Bumps once per cache rebuild — whether the rebuild produced a hot,
  // cold, or refreshed-with-new-signals context. Subscribers (e.g. detail
  // views holding a per-episode score) watch `$contextRevision.stream()`
  // and re-query when it fires; the value itself is uninteresting, only the
  // change events. This is the engine's own change signal, replacing the
  // previous workaround of inferring rebuilds from `topRecommendations`.
  @Broadcasted var contextRevision: Int = 0

  fileprivate init() {}

  // MARK: - Public API

  // Idempotent. Spawns the observation Task that keeps `cache` in sync with
  // the DB. AppLauncher calls this during foreground init; tests call it
  // after seeding their fixture. Public scoring methods do NOT auto-call
  // `start()` — they just read whatever the cache currently has and return
  // empty when it's nil. That keeps every recommendations() call
  // latency-free and pushes "is the cache hot?" to the lifecycle owner.
  func start() {
    startOnce.run {
      startObservingScoringContext()
    }
  }

  // Score an arbitrary set of episodes so a caller can sort a list by "how
  // recommended." Unlike `topRecommendations`, there's no candidate filter,
  // no minimum-score floor, and no limit — every requested episode that has
  // sufficient context gets a score. Callers already have the episodes, so
  // we return just the new info (score + reasons) keyed by ID. Returns
  // empty if `start()` hasn't yet hydrated the cache.
  func recommendations(
    for episodes: [Episode]
  ) async throws -> [Episode.ID: RecommendationScore] {
    guard !episodes.isEmpty else { return [:] }
    guard let context = cache() else { return [:] }
    let candidates = episodes.map {
      CandidateEpisode(id: $0.id, podcastID: $0.podcastID, pubDate: $0.pubDate)
    }
    let scores = try await scoreEpisodes(candidates, context: context)
    let displayMax = observedMaxScore()
    return scores.mapValues { $0.rescaledForDisplay(max: displayMax) }
  }

  // Single-episode convenience over `recommendations(for:)` for callers
  // that only have an ID (e.g. a detail view). Returns nil if the episode
  // doesn't exist or the cache is cold.
  func recommendation(for episodeID: Episode.ID) async throws -> RecommendationScore? {
    guard let episode = try await repo.episode(episodeID) else { return nil }
    return try await recommendations(for: [episode])[episodeID]
  }

  func topRecommendations(limit: Int = 10) async throws -> [RankedRecommendation] {
    Self.log.debug("Generating top recommendations (limit: \(limit))")
    let totalStart = ContinuousClock.now

    // Direct Container.shared access because SharedState isn't Sendable and
    // @DynamicInjected requires a Sendable type. The property read is @MainActor
    // isolated in practice; onDeck is a Sendable value type so the copy is safe.
    let onDeckID = Container.shared.sharedState().onDeck?.id

    let candidatesStart = ContinuousClock.now
    let candidates = try await recommendationRepo.allCandidateEpisodes(excluding: onDeckID)
    let candidatesDuration = ContinuousClock.now - candidatesStart
    Self.log.debug(
      "perf: allCandidateEpisodes took \(candidatesDuration) for \(candidates.count) candidates"
    )

    guard !candidates.isEmpty, let context = cache() else {
      Self.log.debug(
        """
        perf: topRecommendations returned 0 \
        (\(candidates.isEmpty ? "no candidates" : "cache cold")) \
        in \(ContinuousClock.now - totalStart)
        """
      )
      return []
    }

    let scoresStart = ContinuousClock.now
    let scores = try await scoreEpisodes(candidates, context: context)
    let scoresDuration = ContinuousClock.now - scoresStart
    Self.log.debug(
      """
      perf: scoreEpisodes took \(scoresDuration) \
      for \(candidates.count) candidates (\(scores.count) scored)
      """
    )
    guard !scores.isEmpty else {
      Self.log.debug(
        "perf: topRecommendations returned 0 (no scores) in \(ContinuousClock.now - totalStart)"
      )
      return []
    }

    // Anchor display rescaling to the full pool's max so an episode shown in
    // both upNext and a detail view matches. Computed before the threshold
    // filter so a wholesale low-similarity corpus doesn't pin the anchor at
    // exactly the threshold value.
    let batchMax = scores.values.map(\.value).max() ?? 1.0
    observedMaxScore(batchMax)

    // Sort by score (then pubDate, then id) on the lightweight Episode
    // tuples. Hydration of the listable display rows happens at the
    // consumer; the engine only ranks.
    struct ScoredCandidate {
      let id: Episode.ID
      let pubDate: Date
      let score: RecommendationScore
    }
    let rankStart = ContinuousClock.now
    var ranked = [ScoredCandidate](capacity: candidates.count)
    for candidate in candidates {
      guard let score = scores[candidate.id],
        score.value >= Self.minimumScoreThreshold
      else { continue }
      ranked.append(
        ScoredCandidate(id: candidate.id, pubDate: candidate.pubDate, score: score)
      )
    }
    ranked.sort { a, b in
      if a.score.value != b.score.value { return a.score.value > b.score.value }
      if a.pubDate != b.pubDate { return a.pubDate > b.pubDate }
      return a.id > b.id
    }
    let rankDuration = ContinuousClock.now - rankStart
    Self.log.debug(
      """
      perf: rank+sort took \(rankDuration) \
      (\(ranked.count) above threshold of \(scores.count) scored)
      """
    )

    let topRanked = ranked.prefix(limit)
    var top = [RankedRecommendation](capacity: topRanked.count)
    for entry in topRanked {
      top.append((id: entry.id, score: entry.score.rescaledForDisplay(max: batchMax)))
    }

    let totalDuration = ContinuousClock.now - totalStart
    Self.log.debug(
      """
      perf: topRecommendations(limit: \(limit)) total \(totalDuration) — \
      \(top.count) returned from \(candidates.count) candidates
      """
    )
    return top
  }

  // MARK: - ScoringContext

  // The output of one centroid+affinity build, reused across every
  // `recommendations(for:)` / `topRecommendations()` call until the
  // observation emits a new `ScoringContextInputs`. `whiteningMean` is the
  // corpus-wide cone center carried alongside the centroids so candidate
  // scoring whitens against the same anchor the centroids were built from.
  private struct ScoringContext: Sendable {
    let positiveCentroid: [Float]
    let negativeCentroid: [Float]?
    let podcastAffinities: [Podcast.ID: Float]
    let freshnessCadences: [Podcast.ID: FreshnessCadence]
    let whiteningMean: [Float]?
  }

  // Both triggers funnel through `cacheDebounce` so RefreshManager bulk
  // inserts (observatory) and rapid onDeck transitions (nil → new) collapse
  // into a single rebuild after the burst settles. The action always
  // re-fetches inputs so whichever trigger wins the debounce sees DB state
  // at fire time, not at trigger time — a partial-signal write that
  // happens between trigger and fire would otherwise be missed.
  private func startObservingScoringContext() {
    Task(priority: taskPriority(.utility)) {
      var retryDelay: Duration = .seconds(1)
      while !Task.isCancelled {
        do {
          for try await _ in observatory.scoringContextInputsWithoutPartialSignals() {
            guard !Task.isCancelled else { return }
            retryDelay = .seconds(1)
            scheduleCacheRebuild()
          }
        } catch {
          Self.log.caughtError("scoringContextInputs observation failed", error)
          try? await sleeper.sleep(for: retryDelay)
          retryDelay = min(retryDelay * 2, .seconds(60))
        }
      }
    }

    // onDeck transitions cover session boundaries that the GRDB observation
    // can't see — partial-listen bitmaps and lastPlayedDate are excluded
    // from its tracked region. `dropFirst()` skips Broadcast's bootstrap
    // emit; the GRDB observation above already populates the cache from
    // the initial DB state.
    Task(priority: taskPriority(.utility)) {
      let sharedState = Container.shared.sharedState()
      var lastID: Episode.ID? = sharedState.onDeck?.id
      for await onDeck in sharedState.$onDeck.stream().dropFirst() {
        guard !Task.isCancelled else { return }
        let currentID = onDeck?.id
        guard currentID != lastID else { continue }
        lastID = currentID
        scheduleCacheRebuild()
      }
    }

    // The user-controlled limit doesn't affect scoring, so it doesn't
    // invalidate the cache — but it does change how many entries should
    // be published. `dropFirst()` skips the bootstrap emit; whichever
    // path populates the cache first will publish the initial list.
    Task(priority: taskPriority(.utility)) {
      let userSettings = Container.shared.userSettings()
      for await _ in userSettings.$maxRecommendedEpisodesInUpNext.stream().dropFirst() {
        guard !Task.isCancelled else { return }
        scheduleRecommendationsRebuild()
      }
    }

    // Wakes when an episode leaves or rejoins the candidate pool via
    // queue / finish / rate transitions — the cache stays valid (none of
    // those columns affect scoring beyond what the signal observation
    // already covers), so we only need to re-rank, not rebuild context.
    // `dropFirst()` skips the bootstrap; the cache observation above will
    // publish the initial list once context is hot.
    Task(priority: taskPriority(.utility)) {
      var retryDelay: Duration = .seconds(1)
      while !Task.isCancelled {
        do {
          for try await _ in observatory.candidateGateExclusions().dropFirst() {
            guard !Task.isCancelled else { return }
            retryDelay = .seconds(1)
            scheduleRecommendationsRebuild()
          }
        } catch {
          Self.log.caughtError("candidateGateExclusions observation failed", error)
          try? await sleeper.sleep(for: retryDelay)
          retryDelay = min(retryDelay * 2, .seconds(60))
        }
      }
    }
  }

  private func scheduleCacheRebuild() {
    cacheDebounce {
      do {
        let inputsStart = ContinuousClock.now
        let inputs = try await recommendationRepo.allScoringContextInputs()
        let whiteningMean = try await currentWhiteningMean(
          embeddingCount: inputs.embeddingCount,
          currentRevision: Container.shared.contextualEmbedding().revision
        )
        let inputsDuration = ContinuousClock.now - inputsStart
        Self.log.debug(
          """
          perf: allScoringContextInputs took \(inputsDuration) — \
          rated=\(inputs.ratedSignals.count) partial=\(inputs.partialSignals.count) \
          embeddings=\(inputs.signalEmbeddings.count) cadences=\(inputs.freshnessCadences.count) \
          whiteningMean=\(whiteningMean == nil ? "nil" : "ready")
          """
        )

        let buildStart = ContinuousClock.now
        let context = Self.buildContext(from: inputs, whiteningMean: whiteningMean)
        let buildDuration = ContinuousClock.now - buildStart
        Self.log.debug(
          "perf: buildContext took \(buildDuration) — context=\(context == nil ? "nil" : "ready")"
        )

        cache(context)
        $contextRevision.update { $0 += 1 }
        scheduleRecommendationsRebuild()
      } catch {
        Self.log.caughtError("scoring context rebuild failed", error)
      }
    }
  }

  // Pushes the current top recommendations to SharedState. Reads the
  // user-controlled limit at fire time, so a slider change between
  // schedule and fire still picks up the latest value. Uses its own
  // debounce so a rapid drag of the slider doesn't trigger a query
  // per intermediate value.
  private func scheduleRecommendationsRebuild() {
    recommendationsDebounce {
      let limit = Container.shared.userSettings().maxRecommendedEpisodesInUpNext
      let sharedState = Container.shared.sharedState()
      guard limit > 0 else {
        sharedState.setTopRecommendations([])
        return
      }
      do {
        let top = try await topRecommendations(limit: limit)
        sharedState.setTopRecommendations(top)
      } catch {
        Self.log.caughtError("top recommendations rebuild failed", error)
      }
    }
  }

  // MARK: - Build Context

  private static func buildContext(
    from inputs: ScoringContextInputs,
    whiteningMean: [Float]?
  ) -> ScoringContext? {
    let totalSignalCount = inputs.ratedSignals.count + inputs.partialSignals.count
    guard totalSignalCount >= minimumDataThreshold else {
      log.debug(
        """
        Not enough signal data (\(totalSignalCount)/\(minimumDataThreshold)), \
        cached context cleared
        """
      )
      return nil
    }

    guard inputs.hasAnyEmbeddings else {
      log.debug("No embeddings computed yet, cached context cleared")
      return nil
    }

    let (positive, negative) = buildCentroids(
      ratedSignals: inputs.ratedSignals,
      partialSignals: inputs.partialSignals,
      embeddings: inputs.signalEmbeddings,
      whiteningMean: whiteningMean
    )
    guard let positiveCentroid = positive else {
      log.debug("No positive centroid (no signal embeddings available), cached context cleared")
      return nil
    }

    return ScoringContext(
      positiveCentroid: positiveCentroid,
      negativeCentroid: negative,
      podcastAffinities: computePodcastAffinities(
        ratedSignals: inputs.ratedSignals,
        partialSignals: inputs.partialSignals
      ),
      freshnessCadences: inputs.freshnessCadences,
      whiteningMean: whiteningMean
    )
  }

  // MARK: - Score Episodes

  private func scoreEpisodes(
    _ candidates: [CandidateEpisode],
    context: ScoringContext
  ) async throws -> [Episode.ID: RecommendationScore] {
    let episodeIDs = candidates.map(\.id)

    let embeddingsStart = ContinuousClock.now
    let embeddings = try await recommendationRepo.embeddings(for: episodeIDs)
    let embeddingsDuration = ContinuousClock.now - embeddingsStart
    Self.log.debug(
      """
      perf: embeddings(for:) took \(embeddingsDuration) \
      for \(episodeIDs.count) ids (\(embeddings.count) returned)
      """
    )

    let mathStart = ContinuousClock.now
    let now = Date()
    var scores = [Episode.ID: RecommendationScore](capacity: candidates.count)
    for candidate in candidates {
      scores[candidate.id] = scoreCandidate(
        embedding: embeddings[id: candidate.id],
        podcastID: candidate.podcastID,
        pubDate: candidate.pubDate,
        positiveCentroid: context.positiveCentroid,
        negativeCentroid: context.negativeCentroid,
        podcastAffinities: context.podcastAffinities,
        freshnessCadence: context.freshnessCadences[candidate.podcastID]
          ?? FreshnessCadence.default,
        whiteningMean: context.whiteningMean,
        now: now
      )
    }
    let mathDuration = ContinuousClock.now - mathStart
    Self.log.debug(
      "perf: scoring math took \(mathDuration) for \(candidates.count) candidates"
    )
    return scores
  }

  // MARK: - Build Centroids

  private static func buildCentroids(
    ratedSignals: [SignalEpisode],
    partialSignals: [PartialSignal],
    embeddings: IdentifiedArray<Episode.ID, EpisodeEmbedding>,
    whiteningMean: [Float]?
  ) -> (positive: [Float]?, negative: [Float]?) {
    let now = Date()
    let capacity = ratedSignals.count + partialSignals.count
    var positiveVectors = [(vector: [Float], weight: Float)](capacity: capacity)
    var negativeVectors = [(vector: [Float], weight: Float)](capacity: capacity)

    for signal in ratedSignals {
      guard let cached = embeddings[id: signal.id] else { continue }
      let vector = whiten(cached.floatVector, mean: whiteningMean)
      let decay = temporalDecay(from: signal.ratingDate, now: now)

      switch signal.rating {
      case .loved:
        positiveVectors.append((vector, lovedWeight * decay))
      case .liked:
        positiveVectors.append((vector, likedWeight * decay))
      case .disliked:
        negativeVectors.append((vector, decay))
      case .notInterested:
        Assert.fatal(
          "buildCentroids received notInterested signal — Episode.hasRatingSignal filter regressed"
        )
      }
    }

    for partial in partialSignals {
      guard let cached = embeddings[id: partial.id] else { continue }
      let weight =
        partialWeight * Float(partial.coverageRatio)
        * temporalDecay(from: partial.lastPlayedDate, now: now)
      positiveVectors.append((whiten(cached.floatVector, mean: whiteningMean), weight))
    }

    let positive = computeWeightedCentroid(positiveVectors)
    let negative = computeWeightedCentroid(negativeVectors)
    return (positive, negative)
  }

  // MARK: - Score Candidate

  private func scoreCandidate(
    embedding: EpisodeEmbedding?,
    podcastID: Podcast.ID,
    pubDate: Date,
    positiveCentroid: [Float],
    negativeCentroid: [Float]?,
    podcastAffinities: [Podcast.ID: Float],
    freshnessCadence: FreshnessCadence,
    whiteningMean: [Float]?,
    now: Date
  ) -> RecommendationScore {
    // Missing embedding → neutral 0.5; dropping the feature would let
    // renormalization promote affinity to weight 1.0 and overrank the candidate.
    let similarityValue: Float
    if let embedding {
      let vector = Self.whiten(embedding.floatVector, mean: whiteningMean)
      var similarity = VectorMath.dotProduct(vector, positiveCentroid)
      if let negativeCentroid {
        similarity -= VectorMath.dotProduct(vector, negativeCentroid)
      }
      // Remap from [-2, 2] to [0, 1]
      similarityValue = (similarity + 2.0) / 4.0
    } else {
      similarityValue = 0.5
    }

    let affinity = podcastAffinities[podcastID] ?? 0
    // Remap from [-1, 1] to [0, 1]
    let remappedAffinity = (affinity + 1.0) / 2.0

    let features: [(weight: Float, value: Float, reason: RecommendationReason)] = [
      (Self.similarityWeight, similarityValue, .similarToLiked),
      (Self.podcastAffinityWeight, remappedAffinity, .podcastAffinity),
    ]
    let baseScore = features.reduce(Float(0)) { sum, feature in
      sum + feature.weight * feature.value
    }

    // Multiplicative gate, not a summand: a year-old daily-news episode
    // drops to ≈0 instead of being capped by a fixed-weight summand.
    let freshness = FreshnessSignal.compute(
      pubDate: pubDate,
      cadence: freshnessCadence,
      now: now
    )
    let score = baseScore * freshness.multiplier

    var reasons = features.filter { $0.value > 0.5 }.map(\.reason)
    if freshness.inPlateau {
      reasons.append(.recentlyPublished)
    }

    return RecommendationScore(value: score, reasons: reasons)
  }

  // MARK: - Podcast Affinity

  private static func computePodcastAffinities(
    ratedSignals: [SignalEpisode],
    partialSignals: [PartialSignal]
  ) -> [Podcast.ID: Float] {
    let capacity = ratedSignals.count + partialSignals.count
    var podcastStats = [Podcast.ID: (positive: Float, negative: Float, total: Float)](
      capacity: capacity
    )

    for signal in ratedSignals {
      var stats = podcastStats[signal.podcastID] ?? (positive: 0, negative: 0, total: 0)
      stats.total += 1

      switch signal.rating {
      case .loved, .liked:
        stats.positive += 1
      case .disliked:
        stats.negative += dislikedAffinityWeight
      case .notInterested:
        Assert.fatal(
          """
          computePodcastAffinities received notInterested signal — \
          Episode.hasRatingSignal filter regressed
          """
        )
      }

      podcastStats[signal.podcastID] = stats
    }

    for partial in partialSignals {
      var stats = podcastStats[partial.podcastID] ?? (positive: 0, negative: 0, total: 0)
      stats.total += 1
      stats.positive += Float(partial.coverageRatio)
      podcastStats[partial.podcastID] = stats
    }

    // Bayesian smoothed affinity: (positive - negative) / (total + prior).
    return podcastStats.mapValues { stats in
      (stats.positive - stats.negative) / (stats.total + affinityPrior)
    }
  }

  // MARK: - Temporal Decay

  private static func temporalDecay(from date: Date?, now: Date) -> Float {
    guard let date else { return 1.0 }
    let daysSince = now.timeIntervalSince(date) / 86400
    guard daysSince > 0 else { return 1.0 }
    // Half-life decay: weight = 0.5^(days / halfLife)
    return Float(pow(0.5, daysSince / decayHalfLifeDays))
  }

  // MARK: - Whitening

  // Returns the current whitening mean, recomputing only when the cached one
  // is stale per `cachedWhiteningMean`'s key. The fast path is a single
  // `ThreadSafe` read; the slow path scans every embedding. See the cache
  // declaration for which signals invalidate.
  private func currentWhiteningMean(
    embeddingCount: Int,
    currentRevision: Int
  ) async throws -> [Float]? {
    let currentRecipeVersion = EmbeddingService.recipeVersion
    if let cached = cachedWhiteningMean(),
      cached.revision == currentRevision,
      cached.recipeVersion == currentRecipeVersion,
      cached.count > 0
    {
      let ratio = Float(embeddingCount) / Float(cached.count)
      if ratio >= Self.whiteningCountShrinkMin, ratio <= Self.whiteningCountGrowthMax {
        return cached.mean
      }
    }

    let computeStart = ContinuousClock.now
    guard let fresh = try await recommendationRepo.whiteningMean() else { return nil }
    Self.log.debug(
      """
      perf: whiteningMean recomputed in \(ContinuousClock.now - computeStart) \
      (count=\(embeddingCount), revision=\(currentRevision), \
      recipeVersion=\(currentRecipeVersion))
      """
    )
    cachedWhiteningMean(
      (
        mean: fresh,
        revision: currentRevision,
        recipeVersion: currentRecipeVersion,
        count: embeddingCount
      )
    )
    return fresh
  }

  // Center against the corpus mean and re-normalize, restoring cosine
  // similarity's dynamic range. NLContextualEmbedding packs all English text
  // into a narrow ~[0.85, 0.99] cone around `mean`; without centering, the
  // [-2, 2] → [0, 1] remap below squashes every candidate into ~[0.50, 0.55].
  // Pass-through when `mean` is nil (cold start before any embedding has been
  // computed) so the engine degrades gracefully instead of refusing to score.
  private static func whiten(_ vector: [Float], mean: [Float]?) -> [Float] {
    guard let mean, mean.count == vector.count else { return vector }
    let centered = vDSP.subtract(vector, mean)
    return VectorMath.normalize(centered)
  }

  // MARK: - Centroid Math

  private static func computeWeightedCentroid(
    _ vectors: [(vector: [Float], weight: Float)]
  ) -> [Float]? {
    guard let first = vectors.first else { return nil }
    let dim = first.vector.count

    var sum = [Float](repeating: 0, count: dim)
    var totalWeight: Float = 0

    for (vector, weight) in vectors where vector.count == dim {
      for i in 0..<dim {
        sum[i] += vector[i] * weight
      }
      totalWeight += weight
    }

    guard totalWeight > 0 else { return nil }
    let centroid = sum.map { $0 / totalWeight }
    return VectorMath.normalize(centroid)
  }
}
