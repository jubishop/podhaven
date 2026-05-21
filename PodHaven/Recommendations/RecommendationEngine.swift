// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging

// MARK: - Types

struct RecommendationScore: Sendable {
  let value: Float
  let reasons: [RecommendationReason]

  // Stretches the [0.5, max] segment onto [0.5, 1.0] so the top observed
  // candidate displays as 100%, leaving sub-baseline scores untouched.
  fileprivate static func rescaledForDisplay(value: Float, max: Float) -> Float {
    guard value > 0.5, max > 0.5 else { return value }
    let stretched = (value - 0.5) * 0.5 / (max - 0.5)
    return Swift.min(1.0, 0.5 + stretched)
  }

  fileprivate func rescaledForDisplay(max: Float) -> RecommendationScore {
    RecommendationScore(
      value: Self.rescaledForDisplay(value: value, max: max),
      reasons: reasons
    )
  }
}

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

  private static let lovedWeight: Float = 1.0
  private static let likedWeight: Float = 0.6
  private static let partialWeight: Float = 0.5
  private static let affinityPrior: Float = 2.0
  private static let dislikedAffinityWeight: Float = 0.4
  private static let decayHalfLifeDays: Double = 180

  // MARK: - Cached Scoring Context

  private let cache = ThreadSafe<ScoringContext?>(nil)
  private let cacheDebounce = Debounce(duration: .milliseconds(400))
  private let recommendationsDebounce = Debounce(duration: .milliseconds(400))
  private let startOnce = Once()

  // Display-rescaling anchor; only `topRecommendations` (full pool) writes it
  // so per-call surfaces share the same denominator. 1.0 until first rebuild.
  private let observedMaxScore = ThreadSafe<Float>(1.0)

  // Recompute the whitening transform only when the corpus turns over enough
  // that the cached mean drifts past ~1% in display-rounded scores.
  private static let whiteningCountGrowthMax: Float = 1.25
  private static let whiteningCountShrinkMin: Float = 0.8

  // Invalidated by any of: model revision change, recipeVersion bump, count
  // moving outside [shrink, growth], or the user enabling exploratory mode
  // when the cached transform was computed with fewer PCs.
  private let cachedWhiteningTransform = ThreadSafe<
    (
      transform: WhiteningTransform, revision: Int, recipeVersion: Int,
      count: Int, principalComponentCount: Int
    )?
  >(nil)

  // Bumps whenever scoring output can change — a context-cache rebuild or a
  // `podcastAffinityWeight` change. Subscribers watch `$scoringRevision.stream()`
  // to know when to re-score; the value itself is uninteresting.
  @Broadcasted var scoringRevision: Int = 0

  fileprivate init() {}

  // MARK: - Public API

  // Idempotent. Public scoring methods do NOT auto-call `start()` — they
  // read whatever the cache currently has and return empty when it's nil.
  func start() {
    startOnce.run {
      startObservations()
    }
  }

  // Unlike `topRecommendations`, there's no candidate filter, no minimum
  // floor, and no limit. Returns empty if `start()` hasn't yet hydrated
  // the cache. Candidates without an `EpisodeEmbedding` row are omitted
  // from the result map, so callers can use map membership as an
  // "is embedded" check.
  func recommendations(
    for episodes: [Episode]
  ) async throws -> [Episode.ID: RecommendationScore] {
    try await recommendations(
      for: episodes.map {
        CandidateEpisode(id: $0.id, podcastID: $0.podcastID, pubDate: $0.pubDate)
      }
    )
  }

  // Scores `candidates` against the current cache, paired with the display
  // anchor. Returns nil when there's nothing to score or the cache is cold.
  private func scoredCandidates(
    _ candidates: [CandidateEpisode]
  ) async throws -> (scores: [Episode.ID: RecommendationScore], displayMax: Float)? {
    guard !candidates.isEmpty else { return nil }
    guard let context = cache() else { return nil }
    let scores = try await scoreEpisodes(candidates, context: context)
    return (scores, observedMaxScore())
  }

  func recommendations(
    for candidates: [CandidateEpisode]
  ) async throws -> [Episode.ID: RecommendationScore] {
    guard let (scores, displayMax) = try await scoredCandidates(candidates) else { return [:] }
    return scores.mapValues { $0.rescaledForDisplay(max: displayMax) }
  }

  func recommendationScores(
    for candidates: [CandidateEpisode]
  ) async throws -> [Episode.ID: Float] {
    guard let (scores, displayMax) = try await scoredCandidates(candidates) else { return [:] }
    return scores.mapValues {
      RecommendationScore.rescaledForDisplay(value: $0.value, max: displayMax)
    }
  }

  // Returns nil if the episode doesn't exist, has no embedding, or the
  // cache is cold.
  func recommendation(for episodeID: Episode.ID) async throws -> RecommendationScore? {
    guard let episode = try await repo.episode(episodeID) else { return nil }
    return try await recommendations(for: [episode])[episodeID]
  }

  // Returns nil while the cache is cold so callers can hide the section
  // instead of rendering a meaningless score.
  func similarityScore(forEmbedding embedding: [Float]) -> Float? {
    guard let context = cache() else { return nil }
    guard embedding.count == context.positiveCentroid.count else { return nil }

    let stripCount = Self.principalComponentStripCount(for: context.deconeMode)
    var scratch = [Float](repeating: 0, count: embedding.count)
    let raw = unsafe embedding.withUnsafeBufferPointer { vec -> Float in
      unsafe scratch.withUnsafeMutableBufferPointer { scratchPtr in
        if let whiteningTransform = context.whiteningTransform {
          unsafe whiteningTransform.apply(vec, strippingTopK: stripCount, into: scratchPtr)
          let projected = UnsafeBufferPointer(scratchPtr)
          return unsafe Self.similarity(
            of: projected,
            positive: context.positiveCentroid,
            negative: context.negativeCentroid
          )
        }
        return unsafe Self.similarity(
          of: vec,
          positive: context.positiveCentroid,
          negative: context.negativeCentroid
        )
      }
    }

    // Same [-2, 2] → [0, 1] remap + display rescale the per-candidate scorer
    // uses, so this surface and recommendation(for:) read on the same scale.
    let similarityValue = (raw + 2.0) / 4.0
    return RecommendationScore.rescaledForDisplay(
      value: similarityValue,
      max: observedMaxScore()
    )
  }

  func topRecommendations(limit: Int = 10) async throws -> [RankedRecommendation] {
    Self.log.debug("Generating top recommendations (limit: \(limit))")
    let totalStart = ContinuousClock.now

    // SharedState isn't Sendable, so it can't go through @DynamicInjected;
    // the actual read is @MainActor-isolated and onDeck is a value type.
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

    // Anchor display rescaling to the full-pool max (before threshold filter)
    // so the same episode reads consistently across upNext and detail views.
    let batchMax = scores.values.map(\.value).max() ?? 1.0
    observedMaxScore(batchMax)

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

  // Frozen snapshot reused until the next rebuild. `deconeMode` is captured
  // here because changing it reshapes the centroids and invalidates the cache.
  private struct ScoringContext: Sendable {
    let positiveCentroid: [Float]
    let negativeCentroid: [Float]?
    let podcastAffinities: [Podcast.ID: Float]
    let freshnessCadences: [Podcast.ID: FreshnessCadence]
    let whiteningTransform: WhiteningTransform?
    let deconeMode: UserSettings.RecommendationDeconeMode
  }

  private static func principalComponentStripCount(
    for mode: UserSettings.RecommendationDeconeMode
  ) -> Int {
    switch mode {
    case .focused: 0
    case .exploratory: WhiteningTransform.principalComponentCount
    }
  }

  // Triggers funnel through `cacheDebounce` so bulk inserts and rapid onDeck
  // transitions collapse into a single rebuild. The action re-fetches inputs
  // at fire time so a write between trigger and fire isn't missed.
  private func startObservations() {
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

    // partial-listen bitmaps and lastPlayedDate are excluded from the GRDB
    // observation's tracked region, so onDeck transitions are how the engine
    // learns about completed listens. `dropFirst()` skips the bootstrap emit;
    // the observation above already covered the initial DB state.
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

    // Limit changes don't invalidate the cache, only how many entries get
    // published.
    Task(priority: taskPriority(.utility)) {
      let userSettings = Container.shared.userSettings()
      for await _ in userSettings.$maxRecommendedEpisodesInUpNext.stream().dropFirst() {
        guard !Task.isCancelled else { return }
        scheduleRecommendationsRebuild()
      }
    }

    // Mode reshapes the centroids, so we need a full cache rebuild.
    Task(priority: taskPriority(.utility)) {
      let userSettings = Container.shared.userSettings()
      for await _ in userSettings.$recommendationDeconeMode.stream().dropFirst() {
        guard !Task.isCancelled else { return }
        scheduleCacheRebuild()
      }
    }

    // Weight is applied live in `scoreEpisodes`, not baked into the cached
    // context, so it needs no rebuild — but every scoring surface still has to
    // re-score: bump `scoringRevision` for the per-list scorers and rebuild the
    // Up Next set.
    Task(priority: taskPriority(.utility)) {
      let userSettings = Container.shared.userSettings()
      for await _ in userSettings.$podcastAffinityWeight.stream().dropFirst() {
        guard !Task.isCancelled else { return }
        $scoringRevision.update { $0 += 1 }
        scheduleRecommendationsRebuild()
      }
    }

    // Candidate-pool transitions (queue / finish / rate) need a re-rank but
    // not a context rebuild — the underlying signal observation already
    // covers the scoring inputs.
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
        let deconeMode = Container.shared.userSettings().recommendationDeconeMode
        let whiteningTransform = try await currentWhiteningTransform(
          embeddingCount: inputs.embeddingCount,
          currentRevision: Container.shared.contextualEmbedding().revision,
          principalComponentCount: Self.principalComponentStripCount(for: deconeMode)
        )
        let inputsDuration = ContinuousClock.now - inputsStart
        Self.log.debug(
          """
          perf: allScoringContextInputs took \(inputsDuration) — \
          rated=\(inputs.ratedSignals.count) partial=\(inputs.partialSignals.count) \
          embeddings=\(inputs.signalEmbeddings.count) cadences=\(inputs.freshnessCadences.count) \
          whiteningTransform=\(whiteningTransform == nil ? "nil" : "ready") \
          deconeMode=\(deconeMode.rawValue)
          """
        )

        let buildStart = ContinuousClock.now
        let context = Self.buildContext(
          from: inputs,
          whiteningTransform: whiteningTransform,
          deconeMode: deconeMode
        )
        let buildDuration = ContinuousClock.now - buildStart
        Self.log.debug(
          "perf: buildContext took \(buildDuration) — context=\(context == nil ? "nil" : "ready")"
        )

        cache(context)
        $scoringRevision.update { $0 += 1 }
        scheduleRecommendationsRebuild()
      } catch {
        Self.log.caughtError("scoring context rebuild failed", error)
      }
    }
  }

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
    whiteningTransform: WhiteningTransform?,
    deconeMode: UserSettings.RecommendationDeconeMode
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
      whiteningTransform: whiteningTransform,
      deconeMode: deconeMode
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
      whiteningTransform: whiteningTransform,
      deconeMode: deconeMode
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
    let affinityWeight = Float(Container.shared.userSettings().podcastAffinityWeight)
    let similarityWeight = max(0, 1.0 - affinityWeight)
    let stripCount = Self.principalComponentStripCount(for: context.deconeMode)
    let dim = context.positiveCentroid.count
    var scratch = [Float](repeating: 0, count: dim)
    var scores = [Episode.ID: RecommendationScore](capacity: candidates.count)
    unsafe scratch.withUnsafeMutableBufferPointer { scratchPtr in
      for candidate in candidates {
        guard let embedding = embeddings[id: candidate.id] else { continue }
        scores[candidate.id] = unsafe scoreCandidate(
          embedding: embedding,
          podcastID: candidate.podcastID,
          pubDate: candidate.pubDate,
          positiveCentroid: context.positiveCentroid,
          negativeCentroid: context.negativeCentroid,
          podcastAffinities: context.podcastAffinities,
          freshnessCadence: context.freshnessCadences[candidate.podcastID]
            ?? FreshnessCadence.default,
          whiteningTransform: context.whiteningTransform,
          stripCount: stripCount,
          similarityWeight: similarityWeight,
          affinityWeight: affinityWeight,
          scratch: scratchPtr,
          now: now
        )
      }
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
    whiteningTransform: WhiteningTransform?,
    deconeMode: UserSettings.RecommendationDeconeMode
  ) -> (positive: [Float]?, negative: [Float]?) {
    let now = Date()
    let stripCount = principalComponentStripCount(for: deconeMode)

    // Size the accumulators from the first available embedding; signals
    // without embeddings are skipped by the passes below anyway.
    let dim: Int? = {
      for signal in ratedSignals {
        if let cached = embeddings[id: signal.id] { return cached.dimension }
      }
      for partial in partialSignals {
        if let cached = embeddings[id: partial.id] { return cached.dimension }
      }
      return nil
    }()
    guard let dim else { return (nil, nil) }

    var positiveSum = [Float](repeating: 0, count: dim)
    var negativeSum = [Float](repeating: 0, count: dim)
    var positiveWeight: Float = 0
    var negativeWeight: Float = 0
    var scratch = [Float](repeating: 0, count: dim)

    unsafe positiveSum.withUnsafeMutableBufferPointer { positivePtr in
      unsafe negativeSum.withUnsafeMutableBufferPointer { negativePtr in
        unsafe scratch.withUnsafeMutableBufferPointer { scratchPtr in
          func accumulate(
            embedding: EpisodeEmbedding,
            weight: Float,
            into target: UnsafeMutableBufferPointer<Float>
          ) {
            unsafe embedding.withFloatBuffer { vec in
              if let whiteningTransform {
                unsafe whiteningTransform.apply(
                  vec,
                  strippingTopK: stripCount,
                  into: scratchPtr
                )
                let projected = UnsafeBufferPointer(scratchPtr)
                unsafe VectorMath.scaledAddInPlace(
                  projected,
                  scalar: weight,
                  into: target
                )
              } else {
                unsafe VectorMath.scaledAddInPlace(
                  vec,
                  scalar: weight,
                  into: target
                )
              }
            }
          }

          for signal in ratedSignals {
            guard let cached = embeddings[id: signal.id] else { continue }
            let decay = temporalDecay(from: signal.ratingDate, now: now)
            switch signal.rating {
            case .loved:
              let w = lovedWeight * decay
              unsafe accumulate(embedding: cached, weight: w, into: positivePtr)
              positiveWeight += w
            case .liked:
              let w = likedWeight * decay
              unsafe accumulate(embedding: cached, weight: w, into: positivePtr)
              positiveWeight += w
            case .disliked:
              unsafe accumulate(embedding: cached, weight: decay, into: negativePtr)
              negativeWeight += decay
            case .notInterested:
              Assert.fatal(
                """
                buildCentroids received notInterested signal — \
                Episode.hasRatingSignal filter regressed
                """
              )
            }
          }

          for partial in partialSignals {
            guard let cached = embeddings[id: partial.id] else { continue }
            let weight =
              partialWeight * Float(partial.coverageRatio)
              * temporalDecay(from: partial.lastPlayedDate, now: now)
            unsafe accumulate(embedding: cached, weight: weight, into: positivePtr)
            positiveWeight += weight
          }
        }
      }
    }

    let positive = positiveWeight > 0 ? VectorMath.normalize(positiveSum) : nil
    let negative = negativeWeight > 0 ? VectorMath.normalize(negativeSum) : nil
    return (positive, negative)
  }

  // MARK: - Score Candidate

  // Pulled out so the same dot-product path runs for whitened and raw inputs
  // without a cross-branch `UnsafeBufferPointer<Float>` assignment.
  private static func similarity(
    of vector: UnsafeBufferPointer<Float>,
    positive: [Float],
    negative: [Float]?
  ) -> Float {
    var similarity = unsafe positive.withUnsafeBufferPointer { posPtr in
      unsafe VectorMath.dotProduct(vector, posPtr)
    }
    if let negative {
      similarity -= unsafe negative.withUnsafeBufferPointer { negPtr in
        unsafe VectorMath.dotProduct(vector, negPtr)
      }
    }
    return similarity
  }

  private func scoreCandidate(
    embedding: EpisodeEmbedding,
    podcastID: Podcast.ID,
    pubDate: Date,
    positiveCentroid: [Float],
    negativeCentroid: [Float]?,
    podcastAffinities: [Podcast.ID: Float],
    freshnessCadence: FreshnessCadence,
    whiteningTransform: WhiteningTransform?,
    stripCount: Int,
    similarityWeight: Float,
    affinityWeight: Float,
    scratch: UnsafeMutableBufferPointer<Float>,
    now: Date
  ) -> RecommendationScore {
    let raw = unsafe embedding.withFloatBuffer { vec -> Float in
      if let whiteningTransform {
        unsafe whiteningTransform.apply(vec, strippingTopK: stripCount, into: scratch)
        let projected = UnsafeBufferPointer(scratch)
        return unsafe Self.similarity(
          of: projected,
          positive: positiveCentroid,
          negative: negativeCentroid
        )
      }
      return unsafe Self.similarity(
        of: vec,
        positive: positiveCentroid,
        negative: negativeCentroid
      )
    }
    // Remap from [-2, 2] to [0, 1]
    let similarityValue = (raw + 2.0) / 4.0

    let affinity = podcastAffinities[podcastID] ?? 0
    // Remap from [-1, 1] to [0, 1]
    let remappedAffinity = (affinity + 1.0) / 2.0

    let features: [(weight: Float, value: Float, reason: RecommendationReason)] = [
      (similarityWeight, similarityValue, .similarToLiked),
      (affinityWeight, remappedAffinity, .podcastAffinity),
    ]
    let baseScore = features.reduce(Float(0)) { sum, feature in
      sum + feature.weight * feature.value
    }

    // Multiplicative gate: a year-old daily-news episode drops to ≈0
    // instead of being capped at the summand's weight.
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
    return Float(pow(0.5, daysSince / decayHalfLifeDays))
  }

  // MARK: - Whitening

  // Hot path: cached transform read. Cold path: one streaming corpus scan
  // plus power iteration. See `cachedWhiteningTransform` for invalidation.
  private func currentWhiteningTransform(
    embeddingCount: Int,
    currentRevision: Int,
    principalComponentCount: Int
  ) async throws -> WhiteningTransform? {
    let currentRecipeVersion = EmbeddingService.recipeVersion
    if let cached = cachedWhiteningTransform(),
      cached.revision == currentRevision,
      cached.recipeVersion == currentRecipeVersion,
      cached.count > 0,
      cached.principalComponentCount >= principalComponentCount
    {
      let ratio = Float(embeddingCount) / Float(cached.count)
      if ratio >= Self.whiteningCountShrinkMin, ratio <= Self.whiteningCountGrowthMax {
        return cached.transform
      }
    }

    let computeStart = ContinuousClock.now
    guard
      let fresh = try await recommendationRepo.whiteningTransform(
        principalComponentCount: principalComponentCount
      )
    else { return nil }
    Self.log.debug(
      """
      perf: whiteningTransform recomputed in \(ContinuousClock.now - computeStart) \
      (count=\(embeddingCount), revision=\(currentRevision), \
      recipeVersion=\(currentRecipeVersion), pcs=\(fresh.principalComponents.count))
      """
    )
    cachedWhiteningTransform(
      (
        transform: fresh,
        revision: currentRevision,
        recipeVersion: currentRecipeVersion,
        count: embeddingCount,
        principalComponentCount: principalComponentCount
      )
    )
    return fresh
  }

}
