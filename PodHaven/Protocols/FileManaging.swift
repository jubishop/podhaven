// Copyright Justin Bishop, 2025

import Foundation

protocol FileManaging {
  // MARK: - Directory Paths

  var temporaryDirectory: URL { get }

  // MARK: - Data Operations

  func writeData(_ data: Data, to url: URL) async throws
  func readData(from url: URL) async throws -> Data

  // MARK: - File Management Operations

  func removeItem(at url: URL) throws
  func moveItem(at sourceURL: URL, to destinationURL: URL) throws
  func createDirectory(
    at url: URL,
    withIntermediateDirectories createIntermediates: Bool,
    attributes: [FileAttributeKey: Any]?
  ) throws
  func createDirectory(
    at url: URL,
    withIntermediateDirectories createIntermediates: Bool
  ) throws

  // MARK: - File Attribute Operations

  func fileExists(atPath path: String) -> Bool
  func fileExists(at url: URL) -> Bool
  func fileSize(for url: URL) throws -> Int64
  func contentsOfDirectory(
    at url: URL,
    includingPropertiesForKeys keys: [URLResourceKey]?,
    options mask: FileManager.DirectoryEnumerationOptions
  ) throws -> [URL]
  func contentsOfDirectory(at url: URL) throws -> [URL]
}

// MARK: - FileManaging Default Implementations

extension FileManaging {
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

  func createDirectory(
    at url: URL,
    withIntermediateDirectories createIntermediates: Bool = true
  ) throws {
    try createDirectory(
      at: url,
      withIntermediateDirectories: createIntermediates,
      attributes: nil
    )
  }

  func fileExists(at url: URL) -> Bool {
    fileExists(atPath: url.path)
  }

  func fileSize(for url: URL) throws -> Int64 {
    let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
    return Int64(resourceValues.fileSize ?? 0)
  }

  func contentsOfDirectory(at url: URL) throws -> [URL] {
    try contentsOfDirectory(
      at: url,
      includingPropertiesForKeys: [.fileSizeKey],
      options: .skipsHiddenFiles
    )
  }
}
