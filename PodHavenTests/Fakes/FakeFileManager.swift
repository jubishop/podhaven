// Copyright Justin Bishop, 2025

import Foundation

@testable import PodHaven

class FakeFileManager: FileManageable {
  // MARK: - State

  private var inMemoryFiles: [URL: Data] = [:]
  private var inMemoryDirectories: Set<URL> = []
  private var fileAttributes: [URL: [FileAttributeKey: Any]] = [:]

  // MARK: - Initialization

  init() {}

  // MARK: - Data Operations

  func writeData(_ data: Data, to url: URL) async throws {
    // Ensure parent directories exist
    let parentURL = url.deletingLastPathComponent()
    if parentURL != url {  // Prevent infinite recursion for root
      inMemoryDirectories.insert(parentURL)
    }

    inMemoryFiles[url] = data
    fileAttributes[url] = [
      .size: data.count,
      .creationDate: Date(),
      .modificationDate: Date(),
    ]
  }

  func readData(from url: URL) async throws -> Data {
    guard let data = inMemoryFiles[url] else {
      throw TestError.fileNotFound(url)
    }
    return data
  }

  // MARK: - File Management Operations

  func removeItem(at url: URL) throws {
    guard inMemoryFiles[url] != nil || inMemoryDirectories.contains(url) else {
      throw TestError.fileNotFound(url)
    }

    // Remove file or directory
    inMemoryFiles.removeValue(forKey: url)
    inMemoryDirectories.remove(url)
    fileAttributes.removeValue(forKey: url)

    // Remove all files/directories that are children of this URL
    let urlString = url.absoluteString
    let keysToRemove = inMemoryFiles.keys.filter { $0.absoluteString.hasPrefix(urlString) }
    for key in keysToRemove {
      inMemoryFiles.removeValue(forKey: key)
      fileAttributes.removeValue(forKey: key)
    }

    let directoriesToRemove = inMemoryDirectories.filter { $0.absoluteString.hasPrefix(urlString) }
    for directory in directoriesToRemove {
      inMemoryDirectories.remove(directory)
    }
  }

  func removeItem(at url: URL) async throws {
    guard inMemoryFiles[url] != nil || inMemoryDirectories.contains(url) else {
      throw TestError.fileNotFound(url)
    }

    // Remove file or directory
    inMemoryFiles.removeValue(forKey: url)
    inMemoryDirectories.remove(url)
    fileAttributes.removeValue(forKey: url)

    // Remove all files/directories that are children of this URL
    let urlString = url.absoluteString
    let keysToRemove = inMemoryFiles.keys.filter { $0.absoluteString.hasPrefix(urlString) }
    for key in keysToRemove {
      inMemoryFiles.removeValue(forKey: key)
      fileAttributes.removeValue(forKey: key)
    }

    let directoriesToRemove = inMemoryDirectories.filter { $0.absoluteString.hasPrefix(urlString) }
    for directory in directoriesToRemove {
      inMemoryDirectories.remove(directory)
    }
  }

  func createDirectory(
    at url: URL,
    withIntermediateDirectories createIntermediates: Bool = true,
    attributes: [FileAttributeKey: Any]? = nil
  ) throws {
    if createIntermediates {
      // Create all intermediate directories
      var currentURL = url
      var componentsToCreate: [URL] = []

      while !inMemoryDirectories.contains(currentURL) && currentURL.pathComponents.count > 1 {
        componentsToCreate.append(currentURL)
        currentURL = currentURL.deletingLastPathComponent()
      }

      for directory in componentsToCreate.reversed() {
        inMemoryDirectories.insert(directory)
        let directoryAttributes =
          attributes ?? [
            .creationDate: Date(),
            .modificationDate: Date(),
          ]
        fileAttributes[directory] = directoryAttributes
      }
    } else {
      // Only create the final directory if parent exists
      let parentURL = url.deletingLastPathComponent()
      if parentURL != url && !inMemoryDirectories.contains(parentURL) {
        throw TestError.directoryNotFound(parentURL)
      }

      inMemoryDirectories.insert(url)
      let directoryAttributes =
        attributes ?? [
          .creationDate: Date(),
          .modificationDate: Date(),
        ]
      fileAttributes[url] = directoryAttributes
    }
  }

  func createDirectory(
    at url: URL,
    withIntermediateDirectories createIntermediates: Bool = true,
    attributes: [FileAttributeKey: Any]? = nil
  ) async throws {
    if createIntermediates {
      // Create all intermediate directories
      var currentURL = url
      var componentsToCreate: [URL] = []

      while !inMemoryDirectories.contains(currentURL) && currentURL.pathComponents.count > 1 {
        componentsToCreate.append(currentURL)
        currentURL = currentURL.deletingLastPathComponent()
      }

      for directory in componentsToCreate.reversed() {
        inMemoryDirectories.insert(directory)
        let directoryAttributes =
          attributes ?? [
            .creationDate: Date(),
            .modificationDate: Date(),
          ]
        fileAttributes[directory] = directoryAttributes
      }
    } else {
      // Only create the final directory if parent exists
      let parentURL = url.deletingLastPathComponent()
      if parentURL != url && !inMemoryDirectories.contains(parentURL) {
        throw TestError.directoryNotFound(parentURL)
      }

      inMemoryDirectories.insert(url)
      let directoryAttributes =
        attributes ?? [
          .creationDate: Date(),
          .modificationDate: Date(),
        ]
      fileAttributes[url] = directoryAttributes
    }
  }

  // MARK: - File Attribute Operations

  func fileExists(at url: URL) -> Bool {
    inMemoryFiles[url] != nil || inMemoryDirectories.contains(url)
  }

  func fileExists(at url: URL) async -> Bool {
    inMemoryFiles[url] != nil || inMemoryDirectories.contains(url)
  }

  func attributesOfItem(at url: URL) throws -> [FileAttributeKey: Any] {
    guard let attributes = fileAttributes[url] else {
      throw TestError.fileNotFound(url)
    }
    return attributes
  }

  func attributesOfItem(at url: URL) async throws -> [FileAttributeKey: Any] {
    guard let attributes = fileAttributes[url] else {
      throw TestError.fileNotFound(url)
    }
    return attributes
  }
}
