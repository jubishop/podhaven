// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation
import GRDB
import Tagged

protocol Queueing: Sendable {
  var nextEpisode: PodcastEpisode? { get async throws }
  func clear() async throws
  func replace(_ episodeIDs: [Episode.ID]) async throws
  func dequeue(_ db: Database, _ episodeIDs: [Episode.ID]) throws
  func dequeue(_ episodeIDs: [Episode.ID]) async throws
  func dequeue(_ episodeID: Episode.ID) async throws
  func insert(_ episodeID: Episode.ID, at newPosition: Int) async throws
  func unshift(_ episodeIDs: [Episode.ID]) async throws
  func unshift(_ episodeID: Episode.ID) async throws
  func append(_ episodeIDs: [Episode.ID]) async throws
  func append(_ episodeID: Episode.ID) async throws
  func updateQueueOrders(_ episodeIDs: [Episode.ID]) async throws
}
