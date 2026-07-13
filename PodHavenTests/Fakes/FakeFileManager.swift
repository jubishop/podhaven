// Copyright Justin Bishop, 2025

import Foundation

@testable import PodHaven

final class FakeFileManager: FileManaging, Sendable {
  // MARK: - State

  private let inMemoryFiles = ThreadSafe<[URL: Data]>([:])
  private let removeItemErrors = ThreadSafe<[URL: any Error & Sendable]>([:])
  private struct FileSizeErrorRule: Sendable {
    var successfulCallsRemaining: Int
    let error: any Error & Sendable
  }
  private let fileSizeErrorRules = ThreadSafe<[URL: FileSizeErrorRule]>([:])

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
    if let error = removeItemErrors({ $0.removeValue(forKey: url) }) { throw error }
    // Match the real FileManager's missing-file error shape so production code
    // discriminating via ErrorKit.isMissingFile behaves the same in tests.
    guard fileExists(atPath: url.path) else {
      throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: url.path])
    }
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

  func containerURL(forSecurityApplicationGroupIdentifier groupIdentifier: String) -> URL? {
    URL(fileURLWithPath: "/tmp/fake/\(groupIdentifier)")
  }

  func setFileSizeError(
    _ error: any Error & Sendable,
    for url: URL,
    afterSuccessfulCalls: Int = 0
  ) {
    fileSizeErrorRules {
      $0[url] = FileSizeErrorRule(successfulCallsRemaining: afterSuccessfulCalls, error: error)
    }
  }

  func setRemoveItemError(_ error: any Error & Sendable, for url: URL) {
    removeItemErrors { $0[url] = error }
  }

  func fileSize(for url: URL) throws -> Int64 {
    if let rule = fileSizeErrorRules()[url] {
      guard rule.successfulCallsRemaining > 0 else {
        fileSizeErrorRules { $0.removeValue(forKey: url) }
        throw rule.error
      }
      fileSizeErrorRules {
        $0[url] = FileSizeErrorRule(
          successfulCallsRemaining: rule.successfulCallsRemaining - 1,
          error: rule.error
        )
      }
    }

    guard let data = inMemoryFiles[url]
    else {
      throw NSError(
        domain: NSCocoaErrorDomain,
        code: CocoaError.fileReadNoSuchFile.rawValue,
        userInfo: [
          NSUnderlyingErrorKey: NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(ENOENT),
            userInfo: [NSFilePathErrorKey: url.path]
          )
        ]
      )
    }

    return Int64(data.count)
  }
}
