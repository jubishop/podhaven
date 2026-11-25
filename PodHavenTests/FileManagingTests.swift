// Copyright Justin Bishop, 2026

import Foundation
import Testing

@testable import PodHaven

@Suite("of FileManaging tests", .container)
struct FileManagingTests {
  enum WriteMethod: CaseIterable, Sendable {
    case asynchronous
    case synchronous
  }

  private let fileManager: any FileManaging = FileManager.default

  @Test(
    "the system file manager replaces a file without changing what an open reader sees",
    arguments: WriteMethod.allCases
  )
  func systemFileManagerReplacesFileAtomically(_ method: WriteMethod) async throws {
    let url = TestFiles.uniqueURL()
    let original = Data(repeating: 1, count: 4096)
    try await write(original, to: url, using: method)
    let reader = try FileHandle(forReadingFrom: url)

    let replacement = Data(repeating: 2, count: 16)
    try await write(replacement, to: url, using: method)

    #expect(try reader.readToEnd() == original)
    try reader.close()
    #expect(try await fileManager.readData(from: url) == replacement)
  }

  private func write(_ data: Data, to url: URL, using method: WriteMethod) async throws {
    switch method {
    case .asynchronous:
      try await fileManager.writeData(data, to: url)
    case .synchronous:
      try fileManager.writeDataSynchronously(data, to: url)
    }
  }
}
