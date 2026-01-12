// Copyright Justin Bishop, 2025

import Foundation

@testable import PodHaven

final class FakeFileManager: FileManaging, Sendable {
  // MARK: - State

  private let inMemoryFiles = ThreadSafe<[URL: Data]>([:])

  // MARK: - Initialization

  init() {}

  // MARK: - Directory Paths

  var temporaryDirectory: URL { URL(fileURLWithPath: "/tmp/fake") }

  // MARK: - Data Operations

  func writeData(_ data: Data, to url: URL) async throws {
    inMemoryFiles[url] = data
  }

  func readData(from url: URL) async throws -> Data {
    guard let data = inMemoryFiles[url]
    else { throw TestError.fileNotFound(url) }

    return data
  }

  // MARK: - File Management Operations

  func removeItem(at url: URL) throws {
    guard fileExists(atPath: url.path) else { throw TestError.fileNotFound(url) }
    inMemoryFiles { files in
      files.removeValue(forKey: url)
      let urlString = url.absoluteString
      let keysToRemove = files.keys.filter { $0.absoluteString.hasPrefix(urlString) }
      for key in keysToRemove {
        files.removeValue(forKey: key)
      }
    }
  }

  func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
    guard let data = inMemoryFiles[sourceURL]
    else { throw TestError.fileNotFound(sourceURL) }

    inMemoryFiles { files in
      files[destinationURL] = data
      files.removeValue(forKey: sourceURL)
    }
  }

  func createDirectory(
    at url: URL,
    withIntermediateDirectories createIntermediates: Bool,
    attributes: [FileAttributeKey: Any]?
  ) throws {}

  // MARK: - File Attribute Operations

  func fileExists(atPath path: String) -> Bool {
    let url = URL(fileURLWithPath: path)
    return inMemoryFiles[url] != nil
  }

  func contentsOfDirectory(
    at url: URL,
    includingPropertiesForKeys keys: [URLResourceKey]?,
    options mask: FileManager.DirectoryEnumerationOptions
  ) throws -> [URL] {
    // Return all files that have this url as a parent directory
    let urlString = url.absoluteString
    return inMemoryFiles().keys
      .filter { fileURL in
        let fileURLString = fileURL.absoluteString

        // Check if file is in this directory (not in subdirectories)
        guard fileURLString.hasPrefix(urlString) else { return false }

        // Ensure it's a direct child (no more slashes after directory)
        let remainingPath = fileURLString.dropFirst(urlString.count)
        return !remainingPath.isEmpty && !remainingPath.dropFirst().contains("/")
      }
      .sorted { $0.absoluteString < $1.absoluteString }
  }

  func fileSize(for url: URL) throws -> Int64 {
    guard let data = inMemoryFiles[url]
    else { throw TestError.fileNotFound(url) }

    return Int64(data.count)
  }
}
