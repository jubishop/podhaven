// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import IdentifiedCollections
import Tagged

@testable import PodHaven

struct FakeRecommendationRepo: Sendable, FakeCallable, Recommending {
  let callOrder = ThreadSafe<Int>(0)
  let callsByType = ThreadSafe<[ObjectIdentifier: [any MethodCalling]]>([:])

  // One-shot error to throw from the next `embedding(for:)` call so tests can
  // pin down how scoring surfaces handle transient embedding-fetch failures.
  // Cleared on use so the next call reaches the real repo.
  let embeddingFetchError = ThreadSafe<(any Error)?>(nil)

  // One-shot suspend for the next matching `embeddings(for:)` call so tests
  // can interleave state changes with an in-flight scoring pass.
  //
  // `pendingRelease` closes a TOCTOU window: the gated call's `shouldGate`
  // decision and its `pendingContinuation` installation happen in two
  // separate locked regions, so a `releaseEmbeddingsGate()` arriving in
  // between would otherwise see a nil continuation and the gated call
  // would suspend forever. With `pendingRelease`, an early release is
  // recorded under lock and the next suspend resumes immediately.
  struct EmbeddingsGateState: Sendable {
    var armedTarget: Set<Episode.ID>?
    var pendingContinuation: CheckedContinuation<Void, Never>?
    var pendingRelease: Bool = false
    var didSuspend: Bool = false
    var didComplete: Bool = false
  }
  let embeddingsGateState = ThreadSafe<EmbeddingsGateState>(EmbeddingsGateState())

  // Sibling gate for `allScoringContextInputs` so tests can suspend an
  // in-flight cache rebuild the same way the embeddings gate suspends an
  // in-flight scoring pass. The same `pendingRelease` TOCTOU guard applies.
  struct ScoringContextInputsGateState: Sendable {
    var armed: Bool = false
    var pendingContinuation: CheckedContinuation<Void, Never>?
    var pendingRelease: Bool = false
    var didSuspend: Bool = false
  }
  let scoringContextInputsGateState = ThreadSafe<ScoringContextInputsGateState>(
    ScoringContextInputsGateState()
  )

  private let recommendationRepo: RecommendationRepo

  init(_ recommendationRepo: RecommendationRepo) {
    self.recommendationRepo = recommendationRepo
  }

  // MARK: - Embeddings Gate (test-facing)

  func armEmbeddingsGate(matching ids: Set<Episode.ID>) {
    // Resume any continuation left over from a previous arm so a re-arm
    // doesn't leak the prior suspended call. The previous gated task would
    // otherwise wedge forever once `pendingContinuation` is overwritten by
    // the next gated invocation.
    let stale = embeddingsGateState { state -> CheckedContinuation<Void, Never>? in
      let pending = state.pendingContinuation
      state.pendingContinuation = nil
      state.pendingRelease = false
      state.armedTarget = ids
      state.didSuspend = false
      state.didComplete = false
      return pending
    }
    stale?.resume()
  }

  func releaseEmbeddingsGate() {
    let continuation = embeddingsGateState { state -> CheckedContinuation<Void, Never>? in
      if let pending = state.pendingContinuation {
        state.pendingContinuation = nil
        return pending
      }
      // Race with an in-flight gated call that's decided to suspend but
      // hasn't yet installed its continuation. Record the release so the
      // upcoming suspend resumes immediately.
      state.pendingRelease = true
      return nil
    }
    continuation?.resume()
  }

  var isEmbeddingsGateSuspended: Bool {
    embeddingsGateState { state in
      state.didSuspend && state.pendingContinuation != nil
    }
  }

  var didEmbeddingsGateComplete: Bool {
    embeddingsGateState { state in
      state.didComplete
    }
  }

  // MARK: - Scoring Context Inputs Gate (test-facing)

  func armScoringContextInputsGate() {
    let stale = scoringContextInputsGateState {
      state -> CheckedContinuation<Void, Never>? in
      let pending = state.pendingContinuation
      state.pendingContinuation = nil
      state.pendingRelease = false
      state.armed = true
      state.didSuspend = false
      return pending
    }
    stale?.resume()
  }

  func releaseScoringContextInputsGate() {
    let continuation = scoringContextInputsGateState {
      state -> CheckedContinuation<Void, Never>? in
      if let pending = state.pendingContinuation {
        state.pendingContinuation = nil
        return pending
      }
      state.pendingRelease = true
      return nil
    }
    continuation?.resume()
  }

  var isScoringContextInputsGateSuspended: Bool {
    scoringContextInputsGateState { state in
      state.didSuspend && state.pendingContinuation != nil
    }
  }

  // MARK: - Recommending

  var db: AppDB.Reader { recommendationRepo.db }

  // MARK: - Recommendation Readers

  func allRatedEpisodes() async throws -> [SignalEpisode] {
    recordCall(methodName: "allRatedEpisodes", parameters: ())
    return try await recommendationRepo.allRatedEpisodes()
  }

  func allUnratedListenedEpisodes() async throws -> [PartialSignal] {
    recordCall(methodName: "allUnratedListenedEpisodes", parameters: ())
    return try await recommendationRepo.allUnratedListenedEpisodes()
  }

  func allCandidateEpisodes() async throws -> [CandidateEpisode] {
    recordCall(methodName: "allCandidateEpisodes", parameters: ())
    return try await recommendationRepo.allCandidateEpisodes()
  }

  func allScoringContextInputs() async throws -> ScoringContextInputs {
    recordCall(methodName: "allScoringContextInputs", parameters: ())
    let shouldGate: Bool = scoringContextInputsGateState { state -> Bool in
      guard state.armed else { return false }
      state.armed = false
      return true
    }
    if shouldGate {
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        let resumeImmediately = scoringContextInputsGateState { state -> Bool in
          if state.pendingRelease {
            state.pendingRelease = false
            state.didSuspend = true
            return true
          }
          state.pendingContinuation = continuation
          state.didSuspend = true
          return false
        }
        if resumeImmediately {
          continuation.resume()
        }
      }
    }
    return try await recommendationRepo.allScoringContextInputs()
  }

  func whiteningTransform(principalComponentCount: Int) async throws -> WhiteningTransform? {
    recordCall(methodName: "whiteningTransform", parameters: principalComponentCount)
    return try await recommendationRepo.whiteningTransform(
      principalComponentCount: principalComponentCount
    )
  }

  // MARK: - Embedding Writers

  func upsertEmbeddings(_ unsaved: [UnsavedEpisodeEmbedding]) async throws {
    recordCall(methodName: "upsertEmbeddings", parameters: unsaved.count)
    try await recommendationRepo.upsertEmbeddings(unsaved)
  }

  func upsertPodcastEmbeddings(_ unsaved: [UnsavedPodcastEmbedding]) async throws {
    recordCall(methodName: "upsertPodcastEmbeddings", parameters: unsaved.count)
    try await recommendationRepo.upsertPodcastEmbeddings(unsaved)
  }

  func touchEmbeddingVerification(
    forEpisodeIDs episodeIDs: [Episode.ID],
    at date: Date
  ) async throws {
    recordCall(methodName: "touchEmbeddingVerification", parameters: episodeIDs.count)
    try await recommendationRepo.touchEmbeddingVerification(
      forEpisodeIDs: episodeIDs,
      at: date
    )
  }

  // MARK: - Embedding Readers

  func hasEmbeddings() async throws -> Bool {
    recordCall(methodName: "hasEmbeddings", parameters: ())
    return try await recommendationRepo.hasEmbeddings()
  }

  func embedding(for episodeID: Episode.ID) async throws -> EpisodeEmbedding? {
    recordCall(methodName: "embedding", parameters: episodeID)
    if let error = embeddingFetchError({ pending in
      let captured = pending
      pending = nil
      return captured
    }) {
      throw error
    }
    return try await recommendationRepo.embedding(for: episodeID)
  }

  func embeddings(for episodeIDs: [Episode.ID]) async throws
    -> IdentifiedArray<Episode.ID, EpisodeEmbedding>
  {
    recordCall(methodName: "embeddings", parameters: episodeIDs)
    let shouldGate: Bool = embeddingsGateState { state -> Bool in
      guard let target = state.armedTarget, Set(episodeIDs) == target else { return false }
      state.armedTarget = nil
      return true
    }
    if shouldGate {
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        let resumeImmediately = embeddingsGateState { state -> Bool in
          if state.pendingRelease {
            state.pendingRelease = false
            state.didSuspend = true
            return true
          }
          state.pendingContinuation = continuation
          state.didSuspend = true
          return false
        }
        if resumeImmediately {
          continuation.resume()
        }
      }
    }
    let embeddings = try await recommendationRepo.embeddings(for: episodeIDs)
    if shouldGate {
      embeddingsGateState { state in
        state.didComplete = true
      }
    }
    return embeddings
  }

  func podcastEmbedding(for podcastID: Podcast.ID) async throws -> PodcastEmbedding? {
    recordCall(methodName: "podcastEmbedding", parameters: podcastID)
    return try await recommendationRepo.podcastEmbedding(for: podcastID)
  }

  func podcastEmbeddings(for podcastIDs: [Podcast.ID]) async throws
    -> IdentifiedArray<Podcast.ID, PodcastEmbedding>
  {
    recordCall(methodName: "podcastEmbeddings", parameters: podcastIDs)
    return try await recommendationRepo.podcastEmbeddings(for: podcastIDs)
  }

  func podcasts(for podcastIDs: [Podcast.ID]) async throws -> IdentifiedArrayOf<Podcast> {
    recordCall(methodName: "podcasts", parameters: podcastIDs)
    return try await recommendationRepo.podcasts(for: podcastIDs)
  }

  func episodes(for episodeIDs: [Episode.ID]) async throws -> [Episode] {
    recordCall(methodName: "episodes", parameters: episodeIDs)
    return try await recommendationRepo.episodes(for: episodeIDs)
  }

  func episodesNeedingEmbeddings(
    revision: Int,
    includeCurrent: Bool = false
  ) async throws -> [Episode.ID] {
    recordCall(
      methodName: "episodesNeedingEmbeddings",
      parameters: (revision, includeCurrent)
    )
    return try await recommendationRepo.episodesNeedingEmbeddings(
      revision: revision,
      includeCurrent: includeCurrent
    )
  }
}
