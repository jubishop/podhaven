// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation
import GRDB
import IdentifiedCollections
import Tagged

protocol Databasing: Sendable {
  var db: any DatabaseReader { get }

  // MARK: - Global Readers

  func allPodcasts(_ filter: SQLExpression) async throws -> [Podcast]
  func allPodcastSeries(_ filter: SQLExpression, order: SQLOrdering, limit: Int, includeTags: Bool)
    async throws
    -> [PodcastSeries]

  // MARK: - Series Readers

  func podcastSeries(_ podcastID: Podcast.ID) async throws -> PodcastSeries?
  func podcastSeries(_ feedURL: FeedURL, iTunesID: ITunesPodcastID?) async throws -> PodcastSeries?

  // MARK: - Podcast Readers

  func podcast(_ podcastID: Podcast.ID) async throws -> Podcast?

  // MARK: - Episode Readers

  func episode(_ episodeID: Episode.ID) async throws -> Episode?
  func episode(_ mediaGUID: MediaGUID) async throws -> Episode?
  func episode(_ downloadTaskID: URLSessionDownloadTask.ID) async throws -> Episode?
  func episodes(_ downloadTaskIDs: [URLSessionDownloadTask.ID]) async throws -> [Episode]
  func podcastEpisode(_ episodeID: Episode.ID) async throws -> PodcastEpisode?
  func podcastEpisodes(_ episodeIDs: [Episode.ID]) async throws -> [PodcastEpisode]
  func podcastEpisode(_ mediaGUID: MediaGUID) async throws -> PodcastEpisode?
  func latestEpisode(for podcastID: Podcast.ID) async throws -> Episode?
  func cachedEpisodes() async throws -> [Episode]

  // MARK: - Series Writers

  @discardableResult
  func insertSeries(_ unsavedPodcastSeries: UnsavedPodcastSeries) async throws
    -> PodcastSeries

  @discardableResult
  func updateSeriesFromFeed(
    podcastSeries: PodcastSeries,
    podcast: Podcast?,
    unsavedEpisodes: [UnsavedEpisode],
    existingEpisodes: [Episode]
  ) async throws -> [Episode]

  // MARK: - Podcast Writers

  @discardableResult
  func deletePodcast(_ podcastIDs: [Podcast.ID]) async throws -> Int

  @discardableResult
  func deletePodcast(_ podcastID: Podcast.ID) async throws -> Bool

  // MARK: - Tag Writers

  @discardableResult
  func insertTag(_ unsavedTag: UnsavedTag) async throws -> Tag

  @discardableResult
  func renameTag(_ tagID: Tag.ID, newName: String) async throws -> Bool

  @discardableResult
  func deleteTag(_ tagID: Tag.ID) async throws -> Bool

  func addTag(_ tagID: Tag.ID, to podcastID: Podcast.ID) async throws

  @discardableResult
  func removeTag(_ tagID: Tag.ID, from podcastID: Podcast.ID) async throws -> Bool

  func addTag(_ tagID: Tag.ID, to episodeID: Episode.ID) async throws

  @discardableResult
  func removeTag(_ tagID: Tag.ID, from episodeID: Episode.ID) async throws -> Bool

  // MARK: - Episode Writers

  @discardableResult
  func upsertPodcastEpisodes(_ unsavedPodcastEpisodes: [UnsavedPodcastEpisode])
    async throws -> [PodcastEpisode]

  @discardableResult
  func upsertPodcastEpisode(_ unsavedPodcastEpisode: UnsavedPodcastEpisode) async throws
    -> PodcastEpisode

  // MARK: - Episode Attribute Writers

  @discardableResult
  func updateDuration(_ episodeID: Episode.ID, duration: CMTime) async throws -> Bool

  @discardableResult
  func updateCurrentTime(_ episodeID: Episode.ID, currentTime: CMTime) async throws -> Bool

  @discardableResult
  func updatePlayback(
    _ episodeID: Episode.ID,
    currentTime: CMTime,
    playedFrom: CMTime,
    now: Date
  ) async throws -> Bool

  @discardableResult
  func updateDownloadTaskID(_ episodeID: Episode.ID, downloadTaskID: URLSessionDownloadTask.ID?)
    async throws
    -> Bool

  @discardableResult
  func updateCachedFilename(_ episodeID: Episode.ID, cachedFilename: String?) async throws -> Bool

  @discardableResult
  func updateSaveInCache(_ episodeID: Episode.ID, saveInCache: Bool) async throws -> Bool

  @discardableResult
  func updateRating(_ episodeIDs: [Episode.ID], rating: EpisodeRating?) async throws -> Int

  @discardableResult
  func updateRating(_ episodeID: Episode.ID, rating: EpisodeRating?) async throws -> Bool

  @discardableResult
  func markFinished(_ episodeIDs: [Episode.ID]) async throws -> Int

  @discardableResult
  func markFinished(_ episodeID: Episode.ID) async throws -> Bool

  @discardableResult
  func markSubscribed(_ podcastIDs: [Podcast.ID]) async throws -> Int

  @discardableResult
  func markSubscribed(_ podcastID: Podcast.ID) async throws -> Bool

  @discardableResult
  func markUnsubscribed(_ podcastIDs: [Podcast.ID]) async throws -> Int

  @discardableResult
  func markUnsubscribed(_ podcastID: Podcast.ID) async throws -> Bool

  @discardableResult
  func updateITunesID(_ podcastID: Podcast.ID, iTunesID: ITunesPodcastID) async throws -> Bool

  @discardableResult
  func updateLastUpdate(_ podcastID: Podcast.ID) async throws -> Bool

  @discardableResult
  func updateDefaultPlaybackRate(_ podcastID: Podcast.ID, defaultPlaybackRate: Double?) async throws
    -> Bool

  @discardableResult
  func updateQueueAllEpisodes(_ podcastID: Podcast.ID, queueAllEpisodes: QueueAllEpisodes)
    async throws -> Bool

  @discardableResult
  func updateCacheAllEpisodes(_ podcastID: Podcast.ID, cacheAllEpisodes: CacheAllEpisodes)
    async throws -> Bool

  @discardableResult
  func updateNotifyNewEpisodes(_ podcastID: Podcast.ID, notifyNewEpisodes: Bool)
    async throws -> Bool

  @discardableResult
  func updateFreshnessCadence(
    _ podcastID: Podcast.ID,
    freshnessCadence: FreshnessCadence?
  ) async throws -> Bool

  // MARK: - Embedding Writers

  @discardableResult
  func upsertEmbedding(_ unsaved: UnsavedEpisodeEmbedding) async throws -> EpisodeEmbedding
  @discardableResult
  func upsertPodcastEmbedding(_ unsaved: UnsavedPodcastEmbedding) async throws -> PodcastEmbedding

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

  // MARK: - Recommendation Readers

  func allRatedEpisodes() async throws -> [SignalEpisode]
  func allUnratedListenedEpisodes() async throws -> [PartialSignal]
  func allCandidateEpisodes(excluding: Episode.ID?) async throws -> [Episode]
  func allScoringContextInputs() async throws -> ScoringContextInputs
}

extension Databasing {
  func podcastSeries(_ feedURL: FeedURL) async throws -> PodcastSeries? {
    try await podcastSeries(feedURL, iTunesID: nil)
  }
}
