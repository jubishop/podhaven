// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Foundation
import GRDB
import Tagged

extension Container {
  var cacheFileStore: Factory<CacheFileStore> {
    Factory(self) {
      CacheFileStore(writer: self.appDB().writer)
    }
    .scope(.cached)
  }
}

enum CacheFileDisposition: Equatable, Sendable {
  case retained(CachedURL)
  case removed(CachedURL)
  case alreadyMissing(CachedURL)
}

enum CacheFileStorage: Equatable, Sendable {
  case installed(CachedURL)
  case reused(CachedURL)
}

struct CacheFileStore: Sendable {
  private let writer: AppDB.Writer

  fileprivate init(writer: AppDB.Writer) {
    self.writer = writer
  }

  func releaseReference(
    for episodeID: Episode.ID,
    cachedFilename: String
  ) async throws -> CacheFileDisposition? {
    let cachedURL = CacheManager.resolveCachedFilepath(for: cachedFilename)

    return try await writer.write { db in
      let fileManager = Container.shared.fileManager()
      let released =
        try Episode
        .withID(episodeID)
        .filter(Episode.Columns.cachedFilename == cachedFilename)
        .updateAll(db, Episode.Columns.cachedFilename.set(to: nil))
      guard released > 0 else { return nil }

      let referenceCount =
        try Episode
        .filter(Episode.Columns.cachedFilename == cachedFilename)
        .fetchCount(db)
      guard referenceCount == 0 else { return .retained(cachedURL) }

      do {
        try fileManager.removeItem(at: cachedURL.rawValue)
        return .removed(cachedURL)
      } catch {
        guard ErrorKit.isMissingFile(error) else { throw error }
        return .alreadyMissing(cachedURL)
      }
    }
  }

  func discardInvalidFile(
    for episodeID: Episode.ID,
    cachedFilename: String
  ) async throws {
    let cachedURL = CacheManager.resolveCachedFilepath(for: cachedFilename)

    try await writer.write { db in
      let fileManager = Container.shared.fileManager()
      let released =
        try Episode
        .withID(episodeID)
        .filter(Episode.Columns.cachedFilename == cachedFilename)
        .updateAll(db, Episode.Columns.cachedFilename.set(to: nil))
      guard released > 0 else { return }

      do {
        try fileManager.removeItem(at: cachedURL.rawValue)
      } catch {
        guard ErrorKit.isMissingFile(error) else { throw error }
      }
    }
  }

  func removeFileIfUnreferenced(
    _ cachedURL: CachedURL
  ) async throws -> CacheFileDisposition {
    let cachedFilename = cachedURL.lastPathComponent

    return try await writer.write { db in
      let fileManager = Container.shared.fileManager()
      let referenceCount =
        try Episode
        .filter(Episode.Columns.cachedFilename == cachedFilename)
        .fetchCount(db)
      guard referenceCount == 0 else { return .retained(cachedURL) }

      do {
        try fileManager.removeItem(at: cachedURL.rawValue)
        return .removed(cachedURL)
      } catch {
        guard ErrorKit.isMissingFile(error) else { throw error }
        return .alreadyMissing(cachedURL)
      }
    }
  }

  func storeDownloadedFile(
    at sourceURL: URL,
    for episodeID: Episode.ID,
    cachedFilename: String,
    duration: CMTime
  ) async throws -> CacheFileStorage? {
    let cachedURL = CacheManager.resolveCachedFilepath(for: cachedFilename)

    return try await writer.write { db in
      let fileManager = Container.shared.fileManager()
      let existingReferenceCount =
        try Episode
        .filter(Episode.Columns.cachedFilename == cachedFilename)
        .fetchCount(db)
      let updated =
        try Episode
        .withID(episodeID)
        .filter(Episode.Columns.cachedFilename == nil)
        .filter(Episode.Columns.downloading == true)
        .updateAll(
          db,
          Episode.Columns.duration.set(to: duration),
          Episode.Columns.cachedFilename.set(to: cachedFilename),
          Episode.Columns.downloading.set(to: false)
        )
      guard updated > 0 else { return nil }

      if fileManager.fileExists(at: cachedURL.rawValue) {
        guard existingReferenceCount == 0 else { return .reused(cachedURL) }
        do {
          try fileManager.removeItem(at: cachedURL.rawValue)
        } catch {
          guard ErrorKit.isMissingFile(error) else { throw error }
        }
      }

      try fileManager.moveItem(at: sourceURL, to: cachedURL.rawValue)
      return .installed(cachedURL)
    }
  }
}
