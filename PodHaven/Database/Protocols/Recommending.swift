// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import IdentifiedCollections
import Tagged

protocol Recommending: Sendable {
  var db: any DatabaseReader { get }

  // MARK: - Recommendation Readers

  func allRatedEpisodes() async throws -> [SignalEpisode]
  func allUnratedListenedEpisodes() async throws -> [PartialSignal]
  func allCandidateEpisodes(excluding: Episode.ID?) async throws -> [CandidateEpisode]
  func allScoringContextInputs() async throws -> ScoringContextInputs
  func whiteningMean() async throws -> [Float]?

  // MARK: - Embedding Writers

  func upsertEmbeddings(_ unsaved: [UnsavedEpisodeEmbedding]) async throws
  func upsertPodcastEmbeddings(_ unsaved: [UnsavedPodcastEmbedding]) async throws
  func touchEmbeddingVerification(
    forEpisodeIDs episodeIDs: [Episode.ID],
    at date: Date
  ) async throws

  // MARK: - Embedding Readers

  func hasEmbeddings() async throws -> Bool
  func embedding(for episodeID: Episode.ID) async throws -> EpisodeEmbedding?
  func embeddings(for episodeIDs: [Episode.ID]) async throws
    -> IdentifiedArray<Episode.ID, EpisodeEmbedding>
  func podcastEmbedding(for podcastID: Podcast.ID) async throws -> PodcastEmbedding?
  func podcastEmbeddings(for podcastIDs: [Podcast.ID]) async throws
    -> IdentifiedArray<Podcast.ID, PodcastEmbedding>
  func podcasts(for podcastIDs: [Podcast.ID]) async throws -> IdentifiedArrayOf<Podcast>
  func episodes(for episodeIDs: [Episode.ID]) async throws -> [Episode]
  func episodesNeedingEmbeddings(revision: Int) async throws -> [Episode.ID]
}
