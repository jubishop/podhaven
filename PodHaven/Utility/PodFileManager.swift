// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation

extension Container {
  var podFileManager: Factory<FileManageable> {
    Factory(self) { PodFileManager() }.scope(.cached)
  }
}

struct PodFileManager: FileManageable {
  // MARK: - Initialization

  fileprivate init() {}

  // MARK: - Data Operations

  func writeData(_ data: Data, to url: URL) async throws {
    try await withCheckedThrowingContinuation { continuation in
      do {
        try data.write(to: url)
        continuation.resume()
      } catch {
        continuation.resume(throwing: error)
      }
    }
  }

  func readData(from url: URL) async throws -> Data {
    try await withCheckedThrowingContinuation { continuation in
      do {
        let data = try Data(contentsOf: url)
        continuation.resume(returning: data)
      } catch {
        continuation.resume(throwing: error)
      }
    }
  }

  // MARK: - File Management Operations

  func removeItem(at url: URL) async throws {
    try await withCheckedThrowingContinuation { continuation in
      do {
        try FileManager.default.removeItem(at: url)
        continuation.resume()
      } catch {
        continuation.resume(throwing: error)
      }
    }
  }

  func createDirectory(
    at url: URL,
    withIntermediateDirectories createIntermediates: Bool = true
  ) async throws {
    try await withCheckedThrowingContinuation { continuation in
      do {
        try FileManager.default.createDirectory(
          at: url,
          withIntermediateDirectories: createIntermediates,
          attributes: nil
        )
        continuation.resume()
      } catch {
        continuation.resume(throwing: error)
      }
    }
  }

  // MARK: - File Attribute Operations

  func fileExists(at url: URL) async -> Bool {
    await withCheckedContinuation { continuation in
      let exists = FileManager.default.fileExists(atPath: url.path)
      continuation.resume(returning: exists)
    }
  }
}
