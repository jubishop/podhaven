// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation
import GRDB
import Tagged

protocol Databasing: Sendable {
  var db: AppDB.Reader { get }

  // MARK: - Global Readers

  func allPodcasts(_ filter: SQLExpression) async throws -> [Podcast]
  func allPodcastSeries(_ filter: SQLExpression, order: SQLOrdering, limit: Int)
    async throws
    -> [PodcastSeries]

  // MARK: - Series Readers

  func podcastSeries(_ podcastID: Podcast.ID) async throws -> PodcastSeries?
  func podcastSeries(_ feedURL: FeedURL, iTunesID: ITunesPodcastID?) async throws -> PodcastSeries?

  // MARK: - Series Detail Readers

  func podcastSeriesDetail(_ podcastID: Podcast.ID) async throws -> PodcastSeriesDetail?
  func podcastSeriesDetail(_ feedURL: FeedURL, iTunesID: ITunesPodcastID?) async throws
    -> PodcastSeriesDetail?

  // MARK: - Episode Readers

  func episode(_ episodeID: Episode.ID) async throws -> Episode?
  func episodesMatching(
    podcastID: Podcast.ID,
    guids: [GUID],
    mediaURLs: [MediaURL]
  ) async throws -> [Episode]
  func podcastEpisode(_ episodeID: Episode.ID) async throws -> PodcastEpisode?
  func podcastEpisodes(_ episodeIDs: [Episode.ID]) async throws -> [PodcastEpisode]
  func podcastEpisode(_ mediaGUID: MediaGUID, feedURL: FeedURL) async throws -> PodcastEpisode?
  func latestEpisode(for podcastID: Podcast.ID) async throws -> Episode?
  func cachedEpisodes() async throws -> [Episode]
  func downloadingEpisodeIDs() async throws -> [Episode.ID]

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
  func updateTag(_ tagID: Tag.ID, name: String, icon: LucideIcon) async throws -> Bool

  @discardableResult
  func deleteTag(_ tagID: Tag.ID) async throws -> Bool

  func addTag(_ tagID: Tag.ID, to podcastID: Podcast.ID) async throws

  @discardableResult
  func removeTag(_ tagID: Tag.ID, from podcastID: Podcast.ID) async throws -> Bool

  func addTag(_ tagID: Tag.ID, toPodcasts podcastIDs: [Podcast.ID]) async throws

  @discardableResult
  func removeTag(_ tagID: Tag.ID, fromPodcasts podcastIDs: [Podcast.ID]) async throws -> Int

  func addTag(_ tagID: Tag.ID, to episodeID: Episode.ID) async throws

  @discardableResult
  func removeTag(_ tagID: Tag.ID, from episodeID: Episode.ID) async throws -> Bool

  func addTag(_ tagID: Tag.ID, toEpisodes episodeIDs: [Episode.ID]) async throws

  @discardableResult
  func removeTag(_ tagID: Tag.ID, fromEpisodes episodeIDs: [Episode.ID]) async throws -> Int

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
  func claimForDownloadIfUncached(_ episodeID: Episode.ID) async throws -> Bool

  @discardableResult
  func updateDownloading(_ episodeID: Episode.ID, downloading: Bool) async throws -> Bool

  @discardableResult
  func updateCachedFilename(_ episodeID: Episode.ID, cachedFilename: String?) async throws -> Bool

  @discardableResult
  func updateSaveInCache(_ episodeID: Episode.ID, saveInCache: Bool) async throws -> Bool

  @discardableResult
  func updateSaveInCache(_ episodeIDs: [Episode.ID], saveInCache: Bool) async throws -> Int

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

  func updateLastUpdates(_ pairs: [(Podcast.ID, Date)]) async throws

  @discardableResult
  func updatePodcastSettings(_ podcastID: Podcast.ID, _ settings: PodcastSettings) async throws
    -> Bool
}

extension Databasing {
  func podcastSeries(_ feedURL: FeedURL) async throws -> PodcastSeries? {
    try await podcastSeries(feedURL, iTunesID: nil)
  }
}
