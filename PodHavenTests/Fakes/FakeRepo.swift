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
  typealias MarkCompleteCall = RepoCall<Episode.ID>
  typealias MarkSubscribedIDsCall = RepoCall<[Podcast.ID]>
  typealias MarkSubscribedIDCall = RepoCall<Podcast.ID>
  typealias MarkUnsubscribedIDsCall = RepoCall<[Podcast.ID]>
  typealias MarkUnsubscribedIDCall = RepoCall<Podcast.ID>

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

  // MARK: - Call Tracking

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

  // MARK: - Call Filtering

  func calls<T: FakeRepoCall>(of type: T.Type) -> [T] {
    allCallsInOrder.compactMap { $0 as? T }
  }

  func calls(containing substring: String) -> [any FakeRepoCall] {
    allCallsInOrder.filter { $0.toString.contains(substring) }
  }

  func calls(after callOrder: Int) -> [any FakeRepoCall] {
    allCallsInOrder.filter { $0.callOrder > callOrder }
  }

  func calls(methodName: String) -> [any FakeRepoCall] {
    allCallsInOrder.filter { $0.toString.hasPrefix("\(methodName)(") }
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

  func expectCallOrder<T: FakeRepoCall>(_ types: [T.Type]) throws {
    let actualOrder = allCallsInOrder.map { type(of: $0) }
    let expectedTypes = types.map { $0 as Any.Type }

    guard actualOrder.count >= expectedTypes.count else {
      throw FakeRepoError.unexpectedCallOrder(
        expected: expectedTypes.map(String.init(describing:)),
        actual: actualOrder.map(String.init(describing:))
      )
    }

    for (index, expectedType) in expectedTypes.enumerated() {
      guard type(of: actualOrder[index]) == expectedType else {
        throw FakeRepoError.unexpectedCallOrder(
          expected: expectedTypes.map(String.init(describing:)),
          actual: actualOrder.map(String.init(describing:))
        )
      }
    }
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
    allPodcastSeriesCalls.append(
      AllPodcastSeriesCall(
        callOrder: nextCallOrder(),
        methodName: "allPodcastSeries",
        parameters: filter
      )
    )
    return try await repo.allPodcastSeries(filter)
  }

  // MARK: - Series Readers

  func podcastSeries(_ podcastID: Podcast.ID) async throws(RepoError) -> PodcastSeries? {
    podcastSeriesCalls.append(
      PodcastSeriesCall(
        callOrder: nextCallOrder(),
        methodName: "podcastSeries",
        parameters: podcastID
      )
    )
    return try await repo.podcastSeries(podcastID)
  }

  func podcastSeries(_ feedURLs: [FeedURL]) async throws -> IdentifiedArray<FeedURL, PodcastSeries>
  {
    podcastSeriesFeedURLsCalls.append(
      PodcastSeriesFeedURLsCall(
        callOrder: nextCallOrder(),
        methodName: "podcastSeries",
        parameters: feedURLs
      )
    )
    return try await repo.podcastSeries(feedURLs)
  }

  func podcastSeries(_ feedURL: FeedURL) async throws -> PodcastSeries? {
    podcastSeriesFeedURLCalls.append(
      PodcastSeriesFeedURLCall(
        callOrder: nextCallOrder(),
        methodName: "podcastSeries",
        parameters: feedURL
      )
    )
    return try await repo.podcastSeries(feedURL)
  }

  // MARK: - Episode Readers

  func episode(_ episodeID: Episode.ID) async throws -> PodcastEpisode? {
    episodeCalls.append(
      EpisodeCall(callOrder: nextCallOrder(), methodName: "episode", parameters: episodeID)
    )
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
        methodName: "insertSeries",
        parameters: (unsavedPodcast: unsavedPodcast, unsavedEpisodes: unsavedEpisodes)
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
        methodName: "updateSeriesFromFeed",
        parameters: (
          podcastID: podcastID,
          podcast: podcast,
          unsavedEpisodes: unsavedEpisodes,
          existingEpisodes: existingEpisodes
        )
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
      DeletePodcastIDsCall(callOrder: nextCallOrder(), methodName: "delete", parameters: podcastIDs)
    )
    return try await repo.delete(podcastIDs)
  }

  @discardableResult
  func delete(_ podcastID: Podcast.ID) async throws -> Bool {
    deletePodcastIDCalls.append(
      DeletePodcastIDCall(callOrder: nextCallOrder(), methodName: "delete", parameters: podcastID)
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
        methodName: "upsertPodcastEpisodes",
        parameters: unsavedPodcastEpisodes
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
        methodName: "upsertPodcastEpisode",
        parameters: unsavedPodcastEpisode
      )
    )
    return try await repo.upsertPodcastEpisode(unsavedPodcastEpisode)
  }

  @discardableResult
  func updateDuration(_ episodeID: Episode.ID, _ duration: CMTime) async throws -> Bool {
    updateDurationCalls.append(
      UpdateDurationCall(
        callOrder: nextCallOrder(),
        methodName: "updateDuration",
        parameters: (episodeID: episodeID, duration: duration)
      )
    )
    return try await repo.updateDuration(episodeID, duration)
  }

  @discardableResult
  func updateCurrentTime(_ episodeID: Episode.ID, _ currentTime: CMTime) async throws -> Bool {
    updateCurrentTimeCalls.append(
      UpdateCurrentTimeCall(
        callOrder: nextCallOrder(),
        methodName: "updateCurrentTime",
        parameters: (episodeID: episodeID, currentTime: currentTime)
      )
    )
    return try await repo.updateCurrentTime(episodeID, currentTime)
  }

  @discardableResult
  func markComplete(_ episodeID: Episode.ID) async throws -> Bool {
    markCompleteCalls.append(
      MarkCompleteCall(
        callOrder: nextCallOrder(),
        methodName: "markComplete",
        parameters: episodeID
      )
    )
    return try await repo.markComplete(episodeID)
  }

  @discardableResult
  func markSubscribed(_ podcastIDs: [Podcast.ID]) async throws -> Int {
    markSubscribedIDsCalls.append(
      MarkSubscribedIDsCall(
        callOrder: nextCallOrder(),
        methodName: "markSubscribed",
        parameters: podcastIDs
      )
    )
    return try await repo.markSubscribed(podcastIDs)
  }

  @discardableResult
  func markSubscribed(_ podcastID: Podcast.ID) async throws -> Bool {
    markSubscribedIDCalls.append(
      MarkSubscribedIDCall(
        callOrder: nextCallOrder(),
        methodName: "markSubscribed",
        parameters: podcastID
      )
    )
    return try await repo.markSubscribed(podcastID)
  }

  @discardableResult
  func markUnsubscribed(_ podcastIDs: [Podcast.ID]) async throws -> Int {
    markUnsubscribedIDsCalls.append(
      MarkUnsubscribedIDsCall(
        callOrder: nextCallOrder(),
        methodName: "markUnsubscribed",
        parameters: podcastIDs
      )
    )
    return try await repo.markUnsubscribed(podcastIDs)
  }

  @discardableResult
  func markUnsubscribed(_ podcastID: Podcast.ID) async throws -> Bool {
    markUnsubscribedIDCalls.append(
      MarkUnsubscribedIDCall(
        callOrder: nextCallOrder(),
        methodName: "markUnsubscribed",
        parameters: podcastID
      )
    )
    return try await repo.markUnsubscribed(podcastID)
  }

  // MARK: - Private Helpers

  private func nextCallOrder() -> Int {
    callOrder += 1
    return callOrder
  }
}
