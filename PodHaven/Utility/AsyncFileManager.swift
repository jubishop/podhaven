// Copyright Justin Bishop, 2025

import Foundation

enum AsyncFileManager {

  // MARK: - Data Operations

  static func writeData(_ data: Data, to url: URL) async throws {
    try await withCheckedThrowingContinuation { continuation in
      do {
        try data.write(to: url)
        continuation.resume()
      } catch {
        continuation.resume(throwing: error)
      }
    }
  }

  // MARK: - File Management Operations

  static func removeItem(at url: URL) async throws {
    try await withCheckedThrowingContinuation { continuation in
      do {
        try FileManager.default.removeItem(at: url)
        continuation.resume()
      } catch {
        continuation.resume(throwing: error)
      }
    }
  }

  static func createDirectory(
    at url: URL,
    withIntermediateDirectories createIntermediates: Bool = true,
    attributes: [FileAttributeKey: Any]? = nil
  ) async throws {
    try await withCheckedThrowingContinuation { continuation in
      do {
        try FileManager.default.createDirectory(
          at: url,
          withIntermediateDirectories: createIntermediates,
          attributes: attributes
        )
        continuation.resume()
      } catch {
        continuation.resume(throwing: error)
      }
    }
  }

  // MARK: - File Attribute Operations

  static func fileExists(at url: URL) async -> Bool {
    await withCheckedContinuation { continuation in
      let exists = FileManager.default.fileExists(atPath: url.path)
      continuation.resume(returning: exists)
    }
  }

  static func attributesOfItem(at url: URL) async throws -> [FileAttributeKey: Any] {
    try await withCheckedThrowingContinuation { continuation in
      do {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        continuation.resume(returning: attributes)
      } catch {
        continuation.resume(throwing: error)
      }
    }
  }
}
