// Copyright Justin Bishop, 2025

import Foundation

protocol FileManageable {
  // MARK: - Data Operations

  func writeData(_ data: Data, to url: URL) async throws
  func readData(from url: URL) async throws -> Data

  // MARK: - File Management Operations

  func removeItem(at url: URL) throws
  func removeItem(at url: URL) async throws
  func createDirectory(
    at url: URL,
    withIntermediateDirectories createIntermediates: Bool,
    attributes: [FileAttributeKey: Any]?
  ) throws
  func createDirectory(
    at url: URL,
    withIntermediateDirectories createIntermediates: Bool,
    attributes: [FileAttributeKey: Any]?
  ) async throws

  // MARK: - File Attribute Operations

  func fileExists(at url: URL) -> Bool
  func fileExists(at url: URL) async -> Bool
  func attributesOfItem(at url: URL) throws -> [FileAttributeKey: Any]
  func attributesOfItem(at url: URL) async throws -> [FileAttributeKey: Any]
}
