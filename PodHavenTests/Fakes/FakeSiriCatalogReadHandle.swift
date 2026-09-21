// Copyright Justin Bishop, 2026

import Foundation

@testable import PodHaven

final class FakeSiriCatalogReadHandle: SiriCatalogReadHandle, Sendable {
  enum Failure: Error { case read, close }

  let handle: FileHandle
  let readError: Failure?
  let closeError: Failure?
  let requestedCounts = ThreadSafe<[Int]>([])
  let closeCount = ThreadSafe(0)

  init(handle: FileHandle, readError: Failure? = nil, closeError: Failure? = nil) {
    self.handle = handle
    self.readError = readError
    self.closeError = closeError
  }

  func read(upToCount count: Int) throws -> Data? {
    requestedCounts { $0.append(count) }
    if let readError { throw readError }
    return try handle.read(upToCount: count)
  }

  func close() throws {
    closeCount { $0 += 1 }
    try handle.close()
    if let closeError { throw closeError }
  }
}
