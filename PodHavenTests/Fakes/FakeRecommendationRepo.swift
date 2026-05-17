// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import IdentifiedCollections
import Tagged

@testable import PodHaven

struct FakeRecommendationRepo: Sendable, FakeCallable, Recommending {
  let callOrder = ThreadSafe<Int>(0)
  let callsByType = ThreadSafe<[ObjectIdentifier: [any MethodCalling]]>([:])

  // One-shot suspend for the next matching `embeddings(for:)` call so tests
  // can interleave state changes with an in-flight scoring pass.
  struct EmbeddingsGateState: Sendable {
    var armedTarget: Set<Episode.ID>?
    var pendingContinuation: CheckedContinuation<Void, Never>?
    var didSuspend: Bool = false
  }
  let embeddingsGateState = ThreadSafe<EmbeddingsGateState>(EmbeddingsGateState())

  private let recommendationRepo: RecommendationRepo

  init(_ recommendationRepo: RecommendationRepo) {
    self.recommendationRepo = recommendationRepo
  }

  // MARK: - Embeddings Gate (test-facing)

  func armEmbeddingsGate(matching ids: Set<Episode.ID>) {
    embeddingsGateState { state in
      state.armedTarget = ids
      state.didSuspend = false
    }
  }

  func releaseEmbeddingsGate() {
    let continuation = embeddingsGateState { state -> CheckedContinuation<Void, Never>? in
      let pending = state.pendingContinuation
      state.pendingContinuation = nil
      return pending
    }
    continuation?.resume()
  }

  var isEmbeddingsGateSuspended: Bool {
    embeddingsGateState { state in
      state.didSuspend && state.pendingContinuation != nil
    }
  }

  // MARK: - Recommending

  var db: any DatabaseReader { recommendationRepo.db }

  // MARK: - Recommendation Readers

  func allRatedEpisodes() async throws -> [SignalEpisode] {
    recordCall(methodName: "allRatedEpisodes", parameters: ())
    return try await recommendationRepo.allRatedEpisodes()
  }

  func allUnratedListenedEpisodes() async throws -> [PartialSignal] {
    recordCall(methodName: "allUnratedListenedEpisodes", parameters: ())
    return try await recommendationRepo.allUnratedListenedEpisodes()
  }

  func allCandidateEpisodes(
    excluding excludedID: Episode.ID?
  ) async throws -> [CandidateEpisode] {
    recordCall(methodName: "allCandidateEpisodes", parameters: excludedID)
    return try await recommendationRepo.allCandidateEpisodes(excluding: excludedID)
  }

  func allScoringContextInputs() async throws -> ScoringContextInputs {
    recordCall(methodName: "allScoringContextInputs", parameters: ())
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
        embeddingsGateState { state in
          state.pendingContinuation = continuation
          state.didSuspend = true
        }
      }
    }
    return try await recommendationRepo.embeddings(for: episodeIDs)
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

  func episodesNeedingEmbeddings(revision: Int) async throws -> [Episode.ID] {
    recordCall(methodName: "episodesNeedingEmbeddings", parameters: revision)
    return try await recommendationRepo.episodesNeedingEmbeddings(revision: revision)
  }
}
