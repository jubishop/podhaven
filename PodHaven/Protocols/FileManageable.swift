// Copyright Justin Bishop, 2025

import Foundation

protocol FileManageable: Sendable {
  // MARK: - Data Operations

  func writeData(_ data: Data, to url: URL) async throws
  func readData(from url: URL) async throws -> Data

  // MARK: - File Management Operations

  func removeItem(at url: URL) async throws
  func createDirectory(
    at url: URL,
    withIntermediateDirectories createIntermediates: Bool
  ) async throws

  // MARK: - File Attribute Operations

  func fileExists(at url: URL) async -> Bool
}
