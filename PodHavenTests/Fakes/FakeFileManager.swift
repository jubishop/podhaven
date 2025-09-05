// Copyright Justin Bishop, 2025

import Foundation

@testable import PodHaven

final class FakeFileManager: FileManageable, @unchecked Sendable {
  // MARK: - State

  private let inMemoryFiles = ThreadSafe<[URL: Data]>([:])
  private let inMemoryDirectories = ThreadSafe<Set<URL>>([]) // TODO: why do i need this?

  // MARK: - Initialization

  init() {}

  // MARK: - Data Operations

  func writeData(_ data: Data, to url: URL) async throws {
    // Ensure parent directories exist
    let parentURL = url.deletingLastPathComponent()
    if parentURL != url {  // Prevent infinite recursion for root
      inMemoryDirectories { $0.insert(parentURL) }
    }

    inMemoryFiles { $0[url] = data }
  }

  func readData(from url: URL) async throws -> Data {
    if let data = inMemoryFiles({ $0[url] }) {
      return data
    }
    throw TestError.fileNotFound(url)
  }

  // MARK: - File Management Operations

  func removeItem(at url: URL) throws {
    // Check existence
    let exists = inMemoryFiles({ $0[url] != nil }) || inMemoryDirectories({ $0.contains(url) })
    guard exists else { throw TestError.fileNotFound(url) }

    // Remove file or directory
    inMemoryFiles { files in
      files.removeValue(forKey: url)
      let urlString = url.absoluteString
      let keysToRemove = files.keys.filter { $0.absoluteString.hasPrefix(urlString) }
      for key in keysToRemove {
        files.removeValue(forKey: key)
      }
    }
    inMemoryDirectories { dirs in
      dirs.remove(url)
      let urlString = url.absoluteString
      let directoriesToRemove = dirs.filter { $0.absoluteString.hasPrefix(urlString) }
      for directory in directoriesToRemove {
        dirs.remove(directory)
      }
    }
  }

  func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
    // Ensure destination parent directory exists
    let parentURL = destinationURL.deletingLastPathComponent()
    if parentURL != destinationURL {
      inMemoryDirectories { $0.insert(parentURL) }
    }

    // Move: replace destination if it exists
    guard let data = inMemoryFiles({ $0[sourceURL] }) else {
      throw TestError.fileNotFound(sourceURL)
    }

    inMemoryFiles { files in
      files[destinationURL] = data
      files.removeValue(forKey: sourceURL)
    }
  }

  func createDirectory(
    at url: URL,
    withIntermediateDirectories createIntermediates: Bool = true
  ) throws {
    if createIntermediates {
      // Create all intermediate directories
      var currentURL = url
      var componentsToCreate: [URL] = []

      while !inMemoryDirectories({ $0.contains(currentURL) }) && currentURL.pathComponents.count > 1
      {
        componentsToCreate.append(currentURL)
        currentURL = currentURL.deletingLastPathComponent()
      }

      inMemoryDirectories { dirs in
        for directory in componentsToCreate.reversed() {
          dirs.insert(directory)
        }
      }
    } else {
      // Only create the final directory if parent exists
      let parentURL = url.deletingLastPathComponent()
      let parentExists = parentURL == url || inMemoryDirectories({ $0.contains(parentURL) })
      if !parentExists {
        throw TestError.directoryNotFound(parentURL)
      }

      inMemoryDirectories { $0.insert(url) }
    }
  }

  // MARK: - File Attribute Operations

  func fileExists(at url: URL) -> Bool {
    inMemoryFiles({ $0[url] != nil }) || inMemoryDirectories({ $0.contains(url) })
  }
}
