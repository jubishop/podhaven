// Copyright Justin Bishop, 2025

import Foundation

@testable import PodHaven

final class FakeFileManager: FileManageable, Sendable {
  // MARK: - State

  private let inMemoryFiles = ThreadSafe<[URL: Data]>([:])

  // MARK: - Initialization

  init() {}

  // MARK: - Data Operations

  func writeData(_ data: Data, to url: URL) async throws {
    inMemoryFiles { $0[url] = data }
  }

  func readData(from url: URL) async throws -> Data {
    guard let data = inMemoryFiles({ $0[url] })
    else { throw TestError.fileNotFound(url) }

    return data
  }

  // MARK: - File Management Operations

  func removeItem(at url: URL) throws {
    guard fileExists(at: url) else { throw TestError.fileNotFound(url) }
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
    guard let data = inMemoryFiles({ $0[sourceURL] })
    else { throw TestError.fileNotFound(sourceURL) }

    inMemoryFiles { files in
      files[destinationURL] = data
      files.removeValue(forKey: sourceURL)
    }
  }

  func createDirectory(
    at url: URL,
    withIntermediateDirectories createIntermediates: Bool = true
  ) throws {}

  // MARK: - File Attribute Operations

  func fileExists(at url: URL) -> Bool {
    inMemoryFiles({ $0[url] != nil })
  }
}
