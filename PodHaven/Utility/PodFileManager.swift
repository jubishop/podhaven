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

  func removeItem(at url: URL) throws {
    try FileManager.default.removeItem(at: url)
  }

  func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
    try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
  }

  func createDirectory(
    at url: URL,
    withIntermediateDirectories createIntermediates: Bool = true
  ) throws {
    try FileManager.default.createDirectory(
      at: url,
      withIntermediateDirectories: createIntermediates,
      attributes: nil
    )
  }

  // MARK: - File Attribute Operations

  func fileExists(at url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path)
  }
}
