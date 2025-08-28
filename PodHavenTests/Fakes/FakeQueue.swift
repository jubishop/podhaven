// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation
import GRDB
import Tagged

@testable import PodHaven

actor FakeQueue: Sendable, FakeCallable, Queueing {
  var callOrder: Int = 0
  var callsByType: [ObjectIdentifier: [any MethodCalling]] = [:]
  private let queue: any Queueing

  init(_ queue: any Queueing) {
    self.queue = queue
  }

  // MARK: - Queueing

  var nextEpisode: PodcastEpisode? {
    get async throws {
      recordCall(methodName: "nextEpisode", parameters: ())
      return try await queue.nextEpisode
    }
  }

  func clear() async throws {
    recordCall(methodName: "clear", parameters: ())
    try await queue.clear()
  }

  func replace(_ episodeIDs: [Episode.ID]) async throws {
    recordCall(methodName: "replace", parameters: episodeIDs)
    try await queue.replace(episodeIDs)
  }

  nonisolated func dequeue(_ db: Database, _ episodeIDs: [Episode.ID]) throws {
    Task { await recordCall(methodName: "replace", parameters: episodeIDs) }
    try queue.dequeue(db, episodeIDs)
  }

  func dequeue(_ episodeIDs: [Episode.ID]) async throws {
    recordCall(methodName: "dequeue", parameters: episodeIDs)
    try await queue.dequeue(episodeIDs)
  }

  func dequeue(_ episodeID: Episode.ID) async throws {
    recordCall(methodName: "dequeue", parameters: episodeID)
    try await queue.dequeue(episodeID)
  }

  func insert(_ episodeID: Episode.ID, at newPosition: Int) async throws {
    recordCall(
      methodName: "insert",
      parameters: (episodeID: episodeID, newPosition: newPosition)
    )
    try await queue.insert(episodeID, at: newPosition)
  }

  func unshift(_ episodeIDs: [Episode.ID]) async throws {
    recordCall(methodName: "unshift", parameters: episodeIDs)
    try await queue.unshift(episodeIDs)
  }

  func unshift(_ episodeID: Episode.ID) async throws {
    recordCall(methodName: "unshift", parameters: episodeID)
    try await queue.unshift(episodeID)
  }

  func append(_ episodeIDs: [Episode.ID]) async throws {
    recordCall(methodName: "append", parameters: episodeIDs)
    try await queue.append(episodeIDs)
  }

  func append(_ episodeID: Episode.ID) async throws {
    recordCall(methodName: "append", parameters: episodeID)
    try await queue.append(episodeID)
  }

  func updateQueueOrders(_ episodeIDs: [Episode.ID]) async throws {
    recordCall(methodName: "updateQueueOrders", parameters: episodeIDs)
    try await queue.updateQueueOrders(episodeIDs)
  }
}
