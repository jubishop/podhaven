// Copyright Justin Bishop, 2025

import Foundation

protocol FileManageable: Sendable {
  // MARK: - Data Operations

  func writeData(_ data: Data, to url: URL) async throws
  func readData(from url: URL) async throws -> Data

  // MARK: - File Management Operations

  func removeItem(at url: URL) throws
  func moveItem(at sourceURL: URL, to destinationURL: URL) throws
  func createDirectory(
    at url: URL,
    withIntermediateDirectories createIntermediates: Bool
  ) throws

  // MARK: - File Attribute Operations

  func fileExists(at url: URL) -> Bool
  func contentsOfDirectory(at url: URL) throws -> [URL]
  func fileSize(for url: URL) throws -> Int64
}
