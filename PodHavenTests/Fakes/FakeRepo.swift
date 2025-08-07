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

protocol RepoCalling: Sendable {
  var callOrder: Int { get }
  var methodName: String { get }
  var toString: String { get }
}

actor FakeRepo: Databasing, Sendable {
  private let repo: Repo
  private var callOrder: Int = 0

  init(_ repo: Repo) {
    self.repo = repo
  }

  // MARK: - Call Structs

  struct RepoCall<Parameters: Sendable>: RepoCalling {
    let callOrder: Int
    let methodName: String
    let parameters: Parameters
    var toString: String {
      "\(methodName)(\(parameters))"
    }
  }

  private var callsByType: [ObjectIdentifier: [any RepoCalling]] = [:]

  // MARK: - Call Tracking

  private func recordCall<T: RepoCalling>(_ call: T) {
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

  var allCallsInOrder: [any RepoCalling] {
    callsByType.values
      .flatMap { $0 }
      .sorted { $0.callOrder < $1.callOrder }
  }

  // MARK: - Call Filtering

  func calls<T: RepoCalling>(of type: T.Type) -> [T] {
    let key = ObjectIdentifier(type)
    return (callsByType[key] as? [T]) ?? []
  }

  // MARK: - Assertion Helpers

  func expectCalls(methodName: String, count: Int = 1) throws -> [any RepoCalling] {
    let allCalls = callsByType.values.flatMap { $0 }
    let methodMatchingCalls = allCalls.filter { call in
      call.methodName == methodName
    }
    guard methodMatchingCalls.count == count else {
      throw FakeRepoError.unexpectedCallCount(
        expected: count,
        actual: methodMatchingCalls.count,
        type: methodName
      )
    }
    return methodMatchingCalls
  }

  func expectCall<Parameters: Sendable>(methodName: String, parameters: Parameters.Type) throws
    -> RepoCall<Parameters>
  {
    let call = try expectCalls(methodName: methodName).first!
    guard let typedCall = call as? RepoCall<Parameters> else {
      throw FakeRepoError.unexpectedCall(
        type: "RepoCall<\(String(describing: Parameters.self))>.\(methodName)",
        calls: [call.toString]
      )
    }
    return typedCall
  }

  func expectNoCall(methodName: String) throws {
    let allCalls = callsByType.values.flatMap { $0 }
    let methodMatchingCalls = allCalls.filter { call in call.methodName == methodName }
    guard methodMatchingCalls.isEmpty else {
      throw FakeRepoError.unexpectedCall(
        type: methodName,
        calls: methodMatchingCalls.map(\.toString)
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

  func episode(_ episodeID: Episode.ID) async throws -> Episode? {
    recordCall(methodName: "episode", parameters: episodeID)
    return try await repo.episode(episodeID)
  }

  func podcastEpisode(_ episodeID: Episode.ID) async throws -> PodcastEpisode? {
    recordCall(methodName: "podcastEpisode", parameters: episodeID)
    return try await repo.podcastEpisode(episodeID)
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
