// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Tagged

extension Container {
  var silenceStore: Factory<SilenceStore> {
    Factory(self) { SilenceStore(reader: self.appDB().reader, writer: self.appDB().writer) }
      .scope(.cached)
  }
}

struct CachedAudioContent: Codable, FetchableRecord, PersistableRecord, Equatable, Sendable {
  static let databaseTableName = "cachedAudioContent"
  let filename: String
  let generation: String
  var detectorVersion: Int?
  var analysis: Data?
  var failureCount: Int = 0

  var map: SilenceMap? {
    get throws {
      guard detectorVersion == SilenceMap.detectorVersion, let analysis else { return nil }
      guard analysis.count <= 8_000_000 else { throw SilenceAnalysisError.invalidAudio }
      let map = try JSONDecoder().decode(SilenceMap.self, from: analysis)
      guard map.isValid else { throw SilenceAnalysisError.invalidAudio }
      return map
    }
  }
}

struct SilenceCandidate: FetchableRecord, Equatable, Sendable {
  let episodeID: Episode.ID
  let filename: String
  let podcastMode: SilenceMode?
  let queueOrder: Int?

  init(row: Row) {
    episodeID = row[Episode.Columns.id]
    filename = row[Episode.Columns.cachedFilename]
    queueOrder = row[Episode.Columns.queueOrder]
    podcastMode = row.scopes["podcast"]?[Podcast.Columns.silenceMode]
  }
}

struct SilenceStore: Sendable {
  private let reader: AppDB.Reader
  private let writer: AppDB.Writer

  fileprivate init(reader: AppDB.Reader, writer: AppDB.Writer) {
    self.reader = reader
    self.writer = writer
  }

  func observeContent(for filename: String) -> AsyncValueObservation<CachedAudioContent?> {
    reader.observe { db in try CachedAudioContent.fetchOne(db, key: filename) }
  }

  func pruneOrphans() async throws {
    try await writer.write { db in
      let referenced = Set(
        try Episode.select(Episode.Columns.cachedFilename)
          .filter(Episode.Columns.cachedFilename != nil).asRequest(of: String.self).fetchAll(db)
      )
      let saved = try CachedAudioContent.select(Column("filename")).asRequest(of: String.self)
        .fetchAll(db)
      let obsolete = saved.filter { filename in
        !referenced.contains(filename)
          || !Container.shared.fileManager()
            .fileExists(
              at: CacheManager.resolveCachedFilepath(for: filename).rawValue
            )
      }
      try CachedAudioContent.filter(obsolete.contains(Column("filename"))).deleteAll(db)
    }
  }

  func candidates() -> AsyncValueObservation<[SilenceCandidate]> {
    reader.observe { db in
      try Episode.select(
        Episode.Columns.id,
        Episode.Columns.cachedFilename,
        Episode.Columns.queueOrder
      )
      .filter(Episode.Columns.cachedFilename != nil)
      .including(required: Episode.podcast.select(Podcast.Columns.silenceMode))
      .asRequest(of: SilenceCandidate.self)
      .fetchAll(db)
    }
  }

  func content(for filename: String) async throws -> CachedAudioContent? {
    try await writer.write { db in
      let url = CacheManager.resolveCachedFilepath(for: filename)
      guard Container.shared.fileManager().fileExists(at: url.rawValue),
        try Episode.filter(Episode.Columns.cachedFilename == filename).fetchCount(db) > 0
      else {
        try CachedAudioContent.deleteOne(db, key: filename)
        return nil
      }
      if var content = try CachedAudioContent.fetchOne(db, key: filename) {
        if let version = content.detectorVersion, version != SilenceMap.detectorVersion {
          content.analysis = nil
          content.detectorVersion = nil
          content.failureCount = 0
          try content.update(db)
        }
        return content
      }
      let content = CachedAudioContent(filename: filename, generation: UUID().uuidString)
      try content.insert(db)
      return content
    }
  }

  func isCurrent(_ content: CachedAudioContent) async throws -> Bool {
    try await reader.read { db in
      try CachedAudioContent.fetchOne(db, key: content.filename)?.generation == content.generation
        && Container.shared.fileManager()
          .fileExists(
            at: CacheManager.resolveCachedFilepath(for: content.filename).rawValue
          )
    }
  }

  @discardableResult
  func publish(_ map: SilenceMap, for content: CachedAudioContent) async throws -> Bool {
    guard map.isValid else { throw SilenceAnalysisError.invalidAudio }
    let encoded = try JSONEncoder().encode(map)
    guard encoded.count <= 8_000_000 else { throw SilenceAnalysisError.tooManyIntervals }
    return try await writer.write { db in
      guard
        Container.shared.fileManager()
          .fileExists(
            at: CacheManager.resolveCachedFilepath(for: content.filename).rawValue
          )
      else { return false }
      return try CachedAudioContent.filter(Column("filename") == content.filename)
        .filter(Column("generation") == content.generation)
        .updateAll(
          db,
          Column("analysis").set(to: encoded),
          Column("detectorVersion").set(to: SilenceMap.detectorVersion),
          Column("failureCount").set(to: 0)
        ) > 0
    }
  }

  func recordFailure(for content: CachedAudioContent) async throws {
    try await writer.write { db in
      try CachedAudioContent.filter(Column("filename") == content.filename)
        .filter(Column("generation") == content.generation)
        .updateAll(
          db,
          Column("failureCount").set(to: content.failureCount + 1),
          Column("detectorVersion").set(to: SilenceMap.detectorVersion)
        )
    }
  }
}
