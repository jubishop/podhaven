// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation
import GRDB
import IdentifiedCollections
import Tagged

@testable import PodHaven

protocol FakeRepoCall {
  var callOrder: Int { get }
  var toString: String { get }
}

actor FakeRepo: Databasing, Sendable {
  private let repo: Repo
  private var callOrder: Int = 0

  init(_ repo: Repo) {
    self.repo = repo
  }

  // MARK: - Call Tracking

  struct UpdateSeriesFromFeedCall: FakeRepoCall {
    let callOrder: Int
    let podcastID: Podcast.ID
    let podcast: Podcast?
    let unsavedEpisodes: [UnsavedEpisode]
    let existingEpisodes: [Episode]

    var toString: String {
      """
      updateSeriesFromFeed(
        podcastID: \(podcastID), 
        podcast: \(String(describing: podcast?.toString)), 
        unsavedEpisodes: \(unsavedEpisodes.map(\.toString)), 
        existingEpisodes: \(existingEpisodes.map(\.toString)))
      """
    }
  }

  struct InsertSeriesCall: FakeRepoCall {
    let callOrder: Int
    let unsavedPodcast: UnsavedPodcast
    let unsavedEpisodes: [UnsavedEpisode]

    var toString: String {
      """
      insertSeries(
        podcast: \(unsavedPodcast.toString), 
        episodes: \(unsavedEpisodes.map(\.toString)))
      """
    }
  }

  struct AllPodcastSeriesCall: FakeRepoCall {
    let callOrder: Int
    let filter: SQLExpression

    var toString: String {
      "allPodcastSeries(filter: \(filter))"
    }
  }

  struct PodcastSeriesCall: FakeRepoCall {
    let callOrder: Int
    let podcastID: Podcast.ID

    var toString: String {
      "podcastSeries(podcastID: \(podcastID))"
    }
  }

  struct PodcastSeriesFeedURLCall: FakeRepoCall {
    let callOrder: Int
    let feedURL: FeedURL

    var toString: String {
      "podcastSeries(feedURL: \(feedURL))"
    }
  }

  struct PodcastSeriesFeedURLsCall: FakeRepoCall {
    let callOrder: Int
    let feedURLs: [FeedURL]

    var toString: String {
      "podcastSeries(feedURLs: \(feedURLs))"
    }
  }

  struct EpisodeCall: FakeRepoCall {
    let callOrder: Int
    let episodeID: Episode.ID

    var toString: String {
      "episode(episodeID: \(episodeID))"
    }
  }

  struct DeletePodcastIDsCall: FakeRepoCall {
    let callOrder: Int
    let podcastIDs: [Podcast.ID]

    var toString: String {
      "delete(podcastIDs: \(podcastIDs))"
    }
  }

  struct DeletePodcastIDCall: FakeRepoCall {
    let callOrder: Int
    let podcastID: Podcast.ID

    var toString: String {
      "delete(podcastID: \(podcastID))"
    }
  }

  struct UpsertPodcastEpisodesCall: FakeRepoCall {
    let callOrder: Int
    let unsavedPodcastEpisodes: [UnsavedPodcastEpisode]

    var toString: String {
      "upsertPodcastEpisodes(\(unsavedPodcastEpisodes.map(\.toString)))"
    }
  }

  struct UpsertPodcastEpisodeCall: FakeRepoCall {
    let callOrder: Int
    let unsavedPodcastEpisode: UnsavedPodcastEpisode

    var toString: String {
      "upsertPodcastEpisode(episode: \(unsavedPodcastEpisode.toString))"
    }
  }

  struct UpdateDurationCall: FakeRepoCall {
    let callOrder: Int
    let episodeID: Episode.ID
    let duration: CMTime

    var toString: String {
      "updateDuration(episodeID: \(episodeID), duration: \(duration))"
    }
  }

  struct UpdateCurrentTimeCall: FakeRepoCall {
    let callOrder: Int
    let episodeID: Episode.ID
    let currentTime: CMTime

    var toString: String {
      "updateCurrentTime(episodeID: \(episodeID), currentTime: \(currentTime))"
    }
  }

  struct MarkCompleteCall: FakeRepoCall {
    let callOrder: Int
    let episodeID: Episode.ID

    var toString: String {
      "markComplete(episodeID: \(episodeID))"
    }
  }

  struct MarkSubscribedIDsCall: FakeRepoCall {
    let callOrder: Int
    let podcastIDs: [Podcast.ID]

    var toString: String {
      "markSubscribed(podcastIDs: \(podcastIDs))"
    }
  }

  struct MarkSubscribedIDCall: FakeRepoCall {
    let callOrder: Int
    let podcastID: Podcast.ID

    var toString: String {
      "markSubscribed(podcastID: \(podcastID))"
    }
  }

  struct MarkUnsubscribedIDsCall: FakeRepoCall {
    let callOrder: Int
    let podcastIDs: [Podcast.ID]

    var toString: String {
      "markUnsubscribed(podcastIDs: \(podcastIDs))"
    }
  }

  struct MarkUnsubscribedIDCall: FakeRepoCall {
    let callOrder: Int
    let podcastID: Podcast.ID

    var toString: String {
      "markUnsubscribed(podcastID: \(podcastID))"
    }
  }

  private(set) var updateSeriesFromFeedCalls: [UpdateSeriesFromFeedCall] = []
  private(set) var insertSeriesCalls: [InsertSeriesCall] = []
  private(set) var allPodcastSeriesCalls: [AllPodcastSeriesCall] = []
  private(set) var podcastSeriesCalls: [PodcastSeriesCall] = []
  private(set) var podcastSeriesFeedURLCalls: [PodcastSeriesFeedURLCall] = []
  private(set) var podcastSeriesFeedURLsCalls: [PodcastSeriesFeedURLsCall] = []
  private(set) var episodeCalls: [EpisodeCall] = []
  private(set) var deletePodcastIDsCalls: [DeletePodcastIDsCall] = []
  private(set) var deletePodcastIDCalls: [DeletePodcastIDCall] = []
  private(set) var upsertPodcastEpisodesCalls: [UpsertPodcastEpisodesCall] = []
  private(set) var upsertPodcastEpisodeCalls: [UpsertPodcastEpisodeCall] = []
  private(set) var updateDurationCalls: [UpdateDurationCall] = []
  private(set) var updateCurrentTimeCalls: [UpdateCurrentTimeCall] = []
  private(set) var markCompleteCalls: [MarkCompleteCall] = []
  private(set) var markSubscribedIDsCalls: [MarkSubscribedIDsCall] = []
  private(set) var markSubscribedIDCalls: [MarkSubscribedIDCall] = []
  private(set) var markUnsubscribedIDsCalls: [MarkUnsubscribedIDsCall] = []
  private(set) var markUnsubscribedIDCalls: [MarkUnsubscribedIDCall] = []

  private func nextCallOrder() -> Int {
    callOrder += 1
    return callOrder
  }

  func clearAllCalls() {
    callOrder = 0
    updateSeriesFromFeedCalls.removeAll()
    insertSeriesCalls.removeAll()
    allPodcastSeriesCalls.removeAll()
    podcastSeriesCalls.removeAll()
    podcastSeriesFeedURLCalls.removeAll()
    podcastSeriesFeedURLsCalls.removeAll()
    episodeCalls.removeAll()
    deletePodcastIDsCalls.removeAll()
    deletePodcastIDCalls.removeAll()
    upsertPodcastEpisodesCalls.removeAll()
    upsertPodcastEpisodeCalls.removeAll()
    updateDurationCalls.removeAll()
    updateCurrentTimeCalls.removeAll()
    markCompleteCalls.removeAll()
    markSubscribedIDsCalls.removeAll()
    markSubscribedIDCalls.removeAll()
    markUnsubscribedIDsCalls.removeAll()
    markUnsubscribedIDCalls.removeAll()
  }

  var allCallsInOrder: [any FakeRepoCall] {
    var allCalls: [any FakeRepoCall] = []

    allCalls.append(contentsOf: updateSeriesFromFeedCalls)
    allCalls.append(contentsOf: insertSeriesCalls)
    allCalls.append(contentsOf: allPodcastSeriesCalls)
    allCalls.append(contentsOf: podcastSeriesCalls)
    allCalls.append(contentsOf: podcastSeriesFeedURLCalls)
    allCalls.append(contentsOf: podcastSeriesFeedURLsCalls)
    allCalls.append(contentsOf: episodeCalls)
    allCalls.append(contentsOf: deletePodcastIDsCalls)
    allCalls.append(contentsOf: deletePodcastIDCalls)
    allCalls.append(contentsOf: upsertPodcastEpisodesCalls)
    allCalls.append(contentsOf: upsertPodcastEpisodeCalls)
    allCalls.append(contentsOf: updateDurationCalls)
    allCalls.append(contentsOf: updateCurrentTimeCalls)
    allCalls.append(contentsOf: markCompleteCalls)
    allCalls.append(contentsOf: markSubscribedIDsCalls)
    allCalls.append(contentsOf: markSubscribedIDCalls)
    allCalls.append(contentsOf: markUnsubscribedIDsCalls)
    allCalls.append(contentsOf: markUnsubscribedIDCalls)

    return allCalls.sorted { $0.callOrder < $1.callOrder }
  }

  // MARK: - Databasing Protocol

  nonisolated var db: any DatabaseReader {
    repo.db
  }

  // MARK: - Global Readers

  func allPodcasts(_ filter: SQLExpression) async throws -> [Podcast] {
    try await repo.allPodcasts(filter)
  }

  func allPodcastSeries(_ filter: SQLExpression) async throws(RepoError) -> [PodcastSeries] {
    allPodcastSeriesCalls.append(AllPodcastSeriesCall(callOrder: nextCallOrder(), filter: filter))
    return try await repo.allPodcastSeries(filter)
  }

  // MARK: - Series Readers

  func podcastSeries(_ podcastID: Podcast.ID) async throws(RepoError) -> PodcastSeries? {
    podcastSeriesCalls.append(PodcastSeriesCall(callOrder: nextCallOrder(), podcastID: podcastID))
    return try await repo.podcastSeries(podcastID)
  }

  func podcastSeries(_ feedURLs: [FeedURL]) async throws -> IdentifiedArray<FeedURL, PodcastSeries>
  {
    podcastSeriesFeedURLsCalls.append(
      PodcastSeriesFeedURLsCall(callOrder: nextCallOrder(), feedURLs: feedURLs)
    )
    return try await repo.podcastSeries(feedURLs)
  }

  func podcastSeries(_ feedURL: FeedURL) async throws -> PodcastSeries? {
    podcastSeriesFeedURLCalls.append(
      PodcastSeriesFeedURLCall(callOrder: nextCallOrder(), feedURL: feedURL)
    )
    return try await repo.podcastSeries(feedURL)
  }

  // MARK: - Episode Readers

  func episode(_ episodeID: Episode.ID) async throws -> PodcastEpisode? {
    episodeCalls.append(EpisodeCall(callOrder: nextCallOrder(), episodeID: episodeID))
    return try await repo.episode(episodeID)
  }

  // MARK: - Series Writers

  @discardableResult
  func insertSeries(_ unsavedPodcast: UnsavedPodcast, unsavedEpisodes: [UnsavedEpisode])
    async throws(RepoError) -> PodcastSeries
  {
    insertSeriesCalls.append(
      InsertSeriesCall(
        callOrder: nextCallOrder(),
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: unsavedEpisodes
      )
    )
    return try await repo.insertSeries(unsavedPodcast, unsavedEpisodes: unsavedEpisodes)
  }

  func updateSeriesFromFeed(
    podcastID: Podcast.ID,
    podcast: Podcast?,
    unsavedEpisodes: [UnsavedEpisode],
    existingEpisodes: [Episode]
  ) async throws(RepoError) {
    updateSeriesFromFeedCalls.append(
      UpdateSeriesFromFeedCall(
        callOrder: nextCallOrder(),
        podcastID: podcastID,
        podcast: podcast,
        unsavedEpisodes: unsavedEpisodes,
        existingEpisodes: existingEpisodes
      )
    )
    try await repo.updateSeriesFromFeed(
      podcastID: podcastID,
      podcast: podcast,
      unsavedEpisodes: unsavedEpisodes,
      existingEpisodes: existingEpisodes
    )
  }

  // MARK: - Podcast Writers

  @discardableResult
  func delete(_ podcastIDs: [Podcast.ID]) async throws -> Int {
    deletePodcastIDsCalls.append(
      DeletePodcastIDsCall(callOrder: nextCallOrder(), podcastIDs: podcastIDs)
    )
    return try await repo.delete(podcastIDs)
  }

  @discardableResult
  func delete(_ podcastID: Podcast.ID) async throws -> Bool {
    deletePodcastIDCalls.append(
      DeletePodcastIDCall(callOrder: nextCallOrder(), podcastID: podcastID)
    )
    return try await repo.delete(podcastID)
  }

  // MARK: - Episode Writers

  @discardableResult
  func upsertPodcastEpisodes(_ unsavedPodcastEpisodes: [UnsavedPodcastEpisode])
    async throws(RepoError) -> [PodcastEpisode]
  {
    upsertPodcastEpisodesCalls.append(
      UpsertPodcastEpisodesCall(
        callOrder: nextCallOrder(),
        unsavedPodcastEpisodes: unsavedPodcastEpisodes
      )
    )
    return try await repo.upsertPodcastEpisodes(unsavedPodcastEpisodes)
  }

  @discardableResult
  func upsertPodcastEpisode(_ unsavedPodcastEpisode: UnsavedPodcastEpisode) async throws(RepoError)
    -> PodcastEpisode
  {
    upsertPodcastEpisodeCalls.append(
      UpsertPodcastEpisodeCall(
        callOrder: nextCallOrder(),
        unsavedPodcastEpisode: unsavedPodcastEpisode
      )
    )
    return try await repo.upsertPodcastEpisode(unsavedPodcastEpisode)
  }

  @discardableResult
  func updateDuration(_ episodeID: Episode.ID, _ duration: CMTime) async throws -> Bool {
    updateDurationCalls.append(
      UpdateDurationCall(callOrder: nextCallOrder(), episodeID: episodeID, duration: duration)
    )
    return try await repo.updateDuration(episodeID, duration)
  }

  @discardableResult
  func updateCurrentTime(_ episodeID: Episode.ID, _ currentTime: CMTime) async throws -> Bool {
    updateCurrentTimeCalls.append(
      UpdateCurrentTimeCall(
        callOrder: nextCallOrder(),
        episodeID: episodeID,
        currentTime: currentTime
      )
    )
    return try await repo.updateCurrentTime(episodeID, currentTime)
  }

  @discardableResult
  func markComplete(_ episodeID: Episode.ID) async throws -> Bool {
    markCompleteCalls.append(MarkCompleteCall(callOrder: nextCallOrder(), episodeID: episodeID))
    return try await repo.markComplete(episodeID)
  }

  @discardableResult
  func markSubscribed(_ podcastIDs: [Podcast.ID]) async throws -> Int {
    markSubscribedIDsCalls.append(
      MarkSubscribedIDsCall(callOrder: nextCallOrder(), podcastIDs: podcastIDs)
    )
    return try await repo.markSubscribed(podcastIDs)
  }

  @discardableResult
  func markSubscribed(_ podcastID: Podcast.ID) async throws -> Bool {
    markSubscribedIDCalls.append(
      MarkSubscribedIDCall(callOrder: nextCallOrder(), podcastID: podcastID)
    )
    return try await repo.markSubscribed(podcastID)
  }

  @discardableResult
  func markUnsubscribed(_ podcastIDs: [Podcast.ID]) async throws -> Int {
    markUnsubscribedIDsCalls.append(
      MarkUnsubscribedIDsCall(callOrder: nextCallOrder(), podcastIDs: podcastIDs)
    )
    return try await repo.markUnsubscribed(podcastIDs)
  }

  @discardableResult
  func markUnsubscribed(_ podcastID: Podcast.ID) async throws -> Bool {
    markUnsubscribedIDCalls.append(
      MarkUnsubscribedIDCall(callOrder: nextCallOrder(), podcastID: podcastID)
    )
    return try await repo.markUnsubscribed(podcastID)
  }
}
