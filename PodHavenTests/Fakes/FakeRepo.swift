// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation
import GRDB
import IdentifiedCollections
import Tagged

@testable import PodHaven

enum FakeRepoError: Error, CustomStringConvertible {
  case unexpectedCallCount(expected: Int, actual: Int, type: String)
  case unexpectedCall(type: String, calls: [String])
  case unexpectedCallOrder(expected: [String], actual: [String])
  case unexpectedParameters(String)

  var description: String {
    switch self {
    case .unexpectedCallCount(let expected, let actual, let type):
      return "Expected \(expected) calls of type \(type), but got \(actual)"
    case .unexpectedCall(let type, let calls):
      return "Expected no calls of type \(type), but got: \(calls.joined(separator: ", "))"
    case .unexpectedCallOrder(let expected, let actual):
      return
        "Expected call order: \(expected.joined(separator: " -> ")), but got: \(actual.joined(separator: " -> "))"
    case .unexpectedParameters(let message):
      return "Unexpected parameters: \(message)"
    }
  }
}

protocol FakeRepoCall: Sendable {
  var callOrder: Int { get }
  var toString: String { get }
}

actor FakeRepo: Databasing, Sendable {
  private let repo: Repo
  private var callOrder: Int = 0

  init(_ repo: Repo) {
    self.repo = repo
  }

  // MARK: - Call Structs

  struct RepoCall<Parameters: Sendable>: FakeRepoCall {
    let callOrder: Int
    let methodName: String
    let parameters: Parameters
    var toString: String {
      "\(methodName)(\(parameters))"
    }
  }

  typealias UpdateSeriesFromFeedCall = RepoCall<
    (
      podcastID: Podcast.ID, podcast: Podcast?,
      unsavedEpisodes: [UnsavedEpisode],
      existingEpisodes: [Episode]
    )
  >
  typealias InsertSeriesCall = RepoCall<
    (
      unsavedPodcast: UnsavedPodcast,
      unsavedEpisodes: [UnsavedEpisode]
    )
  >
  typealias AllPodcastSeriesCall = RepoCall<SQLExpression>
  typealias PodcastSeriesCall = RepoCall<Podcast.ID>
  typealias PodcastSeriesFeedURLCall = RepoCall<FeedURL>
  typealias PodcastSeriesFeedURLsCall = RepoCall<[FeedURL]>
  typealias EpisodeCall = RepoCall<Episode.ID>
  typealias DeletePodcastIDsCall = RepoCall<[Podcast.ID]>
  typealias DeletePodcastIDCall = RepoCall<Podcast.ID>
  typealias UpsertPodcastEpisodesCall = RepoCall<[UnsavedPodcastEpisode]>
  typealias UpsertPodcastEpisodeCall = RepoCall<UnsavedPodcastEpisode>
  typealias UpdateDurationCall = RepoCall<(episodeID: Episode.ID, duration: CMTime)>
  typealias UpdateCurrentTimeCall = RepoCall<(episodeID: Episode.ID, currentTime: CMTime)>
  typealias UpdateCachedFilenameCall = RepoCall<(episodeID: Episode.ID, cachedFilename: String?)>
  typealias MarkCompleteCall = RepoCall<Episode.ID>
  typealias MarkSubscribedIDsCall = RepoCall<[Podcast.ID]>
  typealias MarkSubscribedIDCall = RepoCall<Podcast.ID>
  typealias MarkUnsubscribedIDsCall = RepoCall<[Podcast.ID]>
  typealias MarkUnsubscribedIDCall = RepoCall<Podcast.ID>

  private var callsByType: [ObjectIdentifier: [any FakeRepoCall]] = [:]

  // MARK: - Call Tracking

  private func recordCall<T: FakeRepoCall>(_ call: T) {
    let key = ObjectIdentifier(T.self)
    callsByType[key, default: []].append(call)
  }

  private func recordCall<Parameters: Sendable>(
    methodName: String,
    parameters: Parameters
  ) {
    recordCall(
      RepoCall(
        callOrder: nextCallOrder(),
        methodName: methodName,
        parameters: parameters
      )
    )
  }

  func clearAllCalls() {
    callOrder = 0
    callsByType.removeAll()
  }

  var allCallsInOrder: [any FakeRepoCall] {
    callsByType.values
      .flatMap { $0 }
      .sorted { $0.callOrder < $1.callOrder }
  }

  // MARK: - Call Filtering

  func calls<T: FakeRepoCall>(of type: T.Type) -> [T] {
    let key = ObjectIdentifier(type)
    return (callsByType[key] as? [T]) ?? []
  }

  // MARK: - Assertion Helpers

  func expectCalls<T: FakeRepoCall>(_ type: T.Type, count: Int = 1) throws -> [T] {
    let matchingCalls = calls(of: type)
    guard matchingCalls.count == count else {
      throw FakeRepoError.unexpectedCallCount(
        expected: count,
        actual: matchingCalls.count,
        type: String(describing: type)
      )
    }
    return matchingCalls
  }

  func expectCall<T: FakeRepoCall>(_ type: T.Type) throws -> T {
    let matchingCalls = try expectCalls(type)
    return matchingCalls.first!
  }

  func expectNoCall<T: FakeRepoCall>(_ type: T.Type) throws {
    let matchingCalls = calls(of: type)
    guard matchingCalls.isEmpty else {
      throw FakeRepoError.unexpectedCall(
        type: String(describing: type),
        calls: matchingCalls.map(\.toString)
      )
    }
  }

  // MARK: - Databasing Protocol

  nonisolated var db: any DatabaseReader { repo.db }

  // MARK: - Global Readers

  func allPodcasts(_ filter: SQLExpression) async throws -> [Podcast] {
    try await repo.allPodcasts(filter)
  }

  func allPodcastSeries(_ filter: SQLExpression) async throws(RepoError) -> [PodcastSeries] {
    recordCall(methodName: "allPodcastSeries", parameters: filter)
    return try await repo.allPodcastSeries(filter)
  }

  // MARK: - Series Readers

  func podcastSeries(_ podcastID: Podcast.ID) async throws(RepoError) -> PodcastSeries? {
    recordCall(methodName: "podcastSeries", parameters: podcastID)
    return try await repo.podcastSeries(podcastID)
  }

  func podcastSeries(_ feedURLs: [FeedURL]) async throws -> IdentifiedArray<FeedURL, PodcastSeries>
  {
    recordCall(methodName: "podcastSeries", parameters: feedURLs)
    return try await repo.podcastSeries(feedURLs)
  }

  func podcastSeries(_ feedURL: FeedURL) async throws -> PodcastSeries? {
    recordCall(methodName: "podcastSeries", parameters: feedURL)
    return try await repo.podcastSeries(feedURL)
  }

  // MARK: - Episode Readers

  func episode(_ episodeID: Episode.ID) async throws -> PodcastEpisode? {
    recordCall(methodName: "episode", parameters: episodeID)
    return try await repo.episode(episodeID)
  }

  func episode(_ episodeID: Episode.ID) async throws -> Episode? {
    recordCall(methodName: "episode", parameters: episodeID)
    return try await repo.episode(episodeID)
  }

  func latestEpisode(for podcastID: Podcast.ID) async throws -> Episode? {
    recordCall(methodName: "latestEpisode", parameters: podcastID)
    return try await repo.latestEpisode(for: podcastID)
  }

  // MARK: - Series Writers

  @discardableResult
  func insertSeries(_ unsavedPodcast: UnsavedPodcast, unsavedEpisodes: [UnsavedEpisode])
    async throws(RepoError) -> PodcastSeries
  {
    recordCall(
      methodName: "insertSeries",
      parameters: (unsavedPodcast: unsavedPodcast, unsavedEpisodes: unsavedEpisodes)
    )
    return try await repo.insertSeries(unsavedPodcast, unsavedEpisodes: unsavedEpisodes)
  }

  func updateSeriesFromFeed(
    podcastID: Podcast.ID,
    podcast: Podcast?,
    unsavedEpisodes: [UnsavedEpisode],
    existingEpisodes: [Episode]
  ) async throws(RepoError) {
    recordCall(
      methodName: "updateSeriesFromFeed",
      parameters: (
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
    recordCall(methodName: "delete", parameters: podcastIDs)
    return try await repo.delete(podcastIDs)
  }

  @discardableResult
  func delete(_ podcastID: Podcast.ID) async throws -> Bool {
    recordCall(methodName: "delete", parameters: podcastID)
    return try await repo.delete(podcastID)
  }

  // MARK: - Episode Writers

  @discardableResult
  func upsertPodcastEpisodes(_ unsavedPodcastEpisodes: [UnsavedPodcastEpisode])
    async throws(RepoError) -> [PodcastEpisode]
  {
    recordCall(methodName: "upsertPodcastEpisodes", parameters: unsavedPodcastEpisodes)
    return try await repo.upsertPodcastEpisodes(unsavedPodcastEpisodes)
  }

  @discardableResult
  func upsertPodcastEpisode(_ unsavedPodcastEpisode: UnsavedPodcastEpisode) async throws(RepoError)
    -> PodcastEpisode
  {
    recordCall(methodName: "upsertPodcastEpisode", parameters: unsavedPodcastEpisode)
    return try await repo.upsertPodcastEpisode(unsavedPodcastEpisode)
  }

  @discardableResult
  func updateDuration(_ episodeID: Episode.ID, _ duration: CMTime) async throws -> Bool {
    recordCall(methodName: "updateDuration", parameters: (episodeID: episodeID, duration: duration))
    return try await repo.updateDuration(episodeID, duration)
  }

  @discardableResult
  func updateCurrentTime(_ episodeID: Episode.ID, _ currentTime: CMTime) async throws -> Bool {
    recordCall(
      methodName: "updateCurrentTime",
      parameters: (episodeID: episodeID, currentTime: currentTime)
    )
    return try await repo.updateCurrentTime(episodeID, currentTime)
  }

  @discardableResult
  func updateCachedFilename(_ episodeID: Episode.ID, _ cachedFilename: String?) async throws -> Bool
  {
    recordCall(
      methodName: "updateCachedFilename",
      parameters: (episodeID: episodeID, cachedFilename: cachedFilename)
    )
    return try await repo.updateCachedFilename(episodeID, cachedFilename)
  }

  @discardableResult
  func markComplete(_ episodeID: Episode.ID) async throws -> Bool {
    recordCall(methodName: "markComplete", parameters: episodeID)
    return try await repo.markComplete(episodeID)
  }

  @discardableResult
  func markSubscribed(_ podcastIDs: [Podcast.ID]) async throws -> Int {
    recordCall(methodName: "markSubscribed", parameters: podcastIDs)
    return try await repo.markSubscribed(podcastIDs)
  }

  @discardableResult
  func markSubscribed(_ podcastID: Podcast.ID) async throws -> Bool {
    recordCall(methodName: "markSubscribed", parameters: podcastID)
    return try await repo.markSubscribed(podcastID)
  }

  @discardableResult
  func markUnsubscribed(_ podcastIDs: [Podcast.ID]) async throws -> Int {
    recordCall(methodName: "markUnsubscribed", parameters: podcastIDs)
    return try await repo.markUnsubscribed(podcastIDs)
  }

  @discardableResult
  func markUnsubscribed(_ podcastID: Podcast.ID) async throws -> Bool {
    recordCall(methodName: "markUnsubscribed", parameters: podcastID)
    return try await repo.markUnsubscribed(podcastID)
  }

  // MARK: - Private Helpers

  private func nextCallOrder() -> Int {
    callOrder += 1
    return callOrder
  }
}
