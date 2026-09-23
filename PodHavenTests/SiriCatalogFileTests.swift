// Copyright Justin Bishop, 2026

import Darwin
import FactoryTesting
import Foundation
import Intents
import Testing

@testable import PodHaven

@Suite("of Siri catalog file I/O", .container)
struct SiriCatalogFileTests {
  private let limit = 32 * 1024 * 1024

  private func withFile(_ body: (SiriCatalogFile) async throws -> Void) async throws {
    let url = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data().write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    try await body(SiriCatalogFile(url: url))
  }

  @Test("an oversized catalog consumes only the accepted bytes and one overflow byte")
  func boundedRead() async throws {
    try await withFile { file in
      let writer = try FileHandle(forWritingTo: file.url)
      try writer.truncate(atOffset: UInt64(limit * 2))
      try writer.close()
      let observer = try FileHandle(forReadingFrom: file.url)
      defer { try? observer.close() }
      let duplicate = dup(observer.fileDescriptor)
      try #require(duplicate >= 0)
      let handle = FakeSiriCatalogReadHandle(
        handle: FileHandle(fileDescriptor: duplicate, closeOnDealloc: true)
      )
      let bounded = SiriCatalogFile(
        url: file.url,
        openForReading: { url in
          #expect(url == file.url)
          return handle
        }
      )
      await #expect(throws: SiriMediaFailure.unavailable) { try await bounded.read() }
      #expect(try observer.offset() == UInt64(limit + 1))
      #expect(handle.requestedCounts() == [limit + 1])
      #expect(handle.closeCount() == 1)
    }
  }

  @Test("the size limit accepts complete JSON and rejects even one excess whitespace byte")
  func sizeBoundary() async throws {
    let catalog = SiriCatalog(entries: [])
    let encoded = try JSONEncoder().encode(catalog)
    try await withFile { file in
      var data = encoded
      data.append(Data(repeating: 0x20, count: limit - encoded.count - 1))
      try data.write(to: file.url)
      #expect(try await file.read().generation == catalog.generation)
      data.append(0x20)
      try data.write(to: file.url)
      #expect(try await file.read().generation == catalog.generation)
      data.append(0x20)
      try data.write(to: file.url)
      await #expect(throws: SiriMediaFailure.unavailable) { try await file.read() }
      let handler = SiriMediaIntentHandler(catalog: file.read, authorized: { true })
      let responses = ThreadSafe<[Int]>([])
      handler.handle(intent: SiriTestIntent.named("One")) { response in
        responses { $0.append(response.code.rawValue) }
      }
      try await Wait.until({ responses().count == 1 }, { "Missing failed callback" })
      #expect(responses() == [INPlayMediaIntentResponseCode.failure.rawValue])
    }
  }

  @Test("successful reads close their descriptor and preserve the complete catalog")
  func roundTrip() async throws {
    let catalog = SiriCatalog(entries: [
      SiriCatalog.Entry(
        identity: SiriMediaIdentity(kind: .podcast, id: 1, feed: "https://podcast.test/feed"),
        title: "A saved show",
        podcastTitle: nil
      )
    ])
    try await withFile { file in
      try file.write(catalog)
      let handle = FakeSiriCatalogReadHandle(handle: try FileHandle(forReadingFrom: file.url))
      let decoded = try await SiriCatalogFile(url: file.url, openForReading: { _ in handle }).read()
      #expect(decoded.generation == catalog.generation)
      #expect(decoded.entries == catalog.entries)
      #expect(decoded.schemaVersion == catalog.schemaVersion)
      #expect(handle.closeCount() == 1)
    }
  }

  @Test(
    "empty, invalid, and unsupported catalogs close their descriptors and cannot hand off",
    arguments: [
      "", "invalid JSON",
      "{\"schemaVersion\":2,\"generation\":\"00000000-0000-0000-0000-000000000000\",\"entries\":[]}",
    ]
  )
  func invalidCatalog(contents: String) async throws {
    try await withFile { file in
      try Data(contents.utf8).write(to: file.url)
      let handle = FakeSiriCatalogReadHandle(handle: try FileHandle(forReadingFrom: file.url))
      let invalid = SiriCatalogFile(url: file.url, openForReading: { _ in handle })
      let handler = SiriMediaIntentHandler(catalog: invalid.read, authorized: { true })
      let responses = ThreadSafe<[Int]>([])
      handler.handle(intent: SiriTestIntent.named("One")) { response in
        responses { $0.append(response.code.rawValue) }
      }
      try await Wait.until({ responses().count == 1 }, { "Missing failed callback" })
      #expect(responses() == [INPlayMediaIntentResponseCode.failure.rawValue])
      #expect(handle.closeCount() == 1)
    }
  }

  @Test("read and close failures propagate after closing", arguments: [false, true])
  func readFailure(closeFails: Bool) async throws {
    try await withFile { file in
      let handle = FakeSiriCatalogReadHandle(
        handle: try FileHandle(forReadingFrom: file.url),
        readError: .read,
        closeError: closeFails ? .close : nil
      )
      let failing = SiriCatalogFile(url: file.url, openForReading: { _ in handle })
      await #expect(throws: FakeSiriCatalogReadHandle.Failure.read) { try await failing.read() }
      #expect(handle.closeCount() == 1)
    }
  }

  @Test("a close failure prevents a successful catalog result")
  func closeFailure() async throws {
    try await withFile { file in
      try file.write(SiriCatalog(entries: []))
      let handle = FakeSiriCatalogReadHandle(
        handle: try FileHandle(forReadingFrom: file.url),
        closeError: .close
      )
      let failing = SiriCatalogFile(url: file.url, openForReading: { _ in handle })
      await #expect(throws: FakeSiriCatalogReadHandle.Failure.close) { try await failing.read() }
      #expect(handle.closeCount() == 1)
    }
  }

  @Test("atomic replacement during open leaves the read on one complete catalog")
  func atomicReplacement() async throws {
    let original = SiriCatalog(entries: [])
    let replacement = SiriCatalog(entries: [])
    try await withFile { file in
      try file.write(original)
      let reading = SiriCatalogFile(
        url: file.url,
        openForReading: { url in
          let handle = try FileHandle(forReadingFrom: url)
          try file.write(replacement)
          return handle
        }
      )
      #expect(try await reading.read().generation == original.generation)
      #expect(try await file.read().generation == replacement.generation)
    }
  }
}
