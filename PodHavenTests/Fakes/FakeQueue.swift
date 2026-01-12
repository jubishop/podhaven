// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation
import GRDB
import Tagged

@testable import PodHaven

// TODO: Make this a struct to avoid Task {
struct FakeQueue: Sendable, FakeCallable, Queueing {
  let callOrder = ThreadSafe<Int>(0)
  let callsByType = ThreadSafe<[ObjectIdentifier: [any MethodCalling]]>([:])

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

  func dequeue(_ db: Database, _ episodeIDs: [Episode.ID]) throws {
    recordCall(methodName: "dequeue", parameters: episodeIDs)
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

  func unshift(_ db: Database, _ episodeIDs: [Episode.ID]) throws {
    recordCall(methodName: "unshift", parameters: episodeIDs)
    try queue.unshift(db, episodeIDs)
  }

  func unshift(_ episodeIDs: [Episode.ID]) async throws {
    recordCall(methodName: "unshift", parameters: episodeIDs)
    try await queue.unshift(episodeIDs)
  }

  func unshift(_ episodeID: Episode.ID) async throws {
    recordCall(methodName: "unshift", parameters: episodeID)
    try await queue.unshift(episodeID)
  }

  func append(_ db: Database, _ episodeIDs: [Episode.ID]) throws {
    recordCall(methodName: "append", parameters: episodeIDs)
    try queue.append(db, episodeIDs)
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

  func enforceMaxQueueLength() async throws {
    recordCall(methodName: "enforceMaxQueueLength", parameters: ())
    try await queue.enforceMaxQueueLength()
  }
}
