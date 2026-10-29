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
    let url = TestFiles.uniqueURL()
    try Data().write(to: url)
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
    let catalog = SiriCatalog(podcasts: [])
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

  @Test("a library twice the largest measured one stays within the limit and resolves")
  func doubledLibrary() async throws {
    // Twice the measured library, with fields matching its average bytes per entry.
    let podcastCount = 2 * 189
    let episodeCount = 2 * 110_822
    func feed(_ podcast: Int) -> String {
      "https://feeds.synthetic.test/podcasts/\(podcast)/feed.xml"
    }
    func show(_ podcast: Int) -> String { "Synthetic Show \(podcast)" }
    func title(_ episode: Int) -> String {
      "Episode \(episode): A longer conversation about science, culture, and the week’s news"
    }
    let catalog = SiriCatalog(
      podcasts: (0..<podcastCount)
        .map { podcast in
          SiriCatalog.Podcast(
            id: Int64(podcast),
            feed: feed(podcast),
            title: show(podcast),
            episodes: stride(from: podcast, to: episodeCount, by: podcastCount)
              .map { episode in
                SiriCatalog.Episode(
                  id: Int64(episode),
                  guid: UUID().uuidString,
                  title: title(episode)
                )
              }
          )
        }
    )
    try await withFile { file in
      let data = try SiriCatalogFile.encode(catalog)
      #expect(data.count <= limit)
      try file.write(data)
      let decoded = try await file.read()
      #expect(decoded.generation == catalog.generation)
      let lastPodcast = podcastCount - 1
      #expect(
        try decoded.matches(SiriTestIntent.named(show(lastPodcast), type: .podcastShow))
          .map(\.identity) == [
            SiriMediaIdentity(kind: .podcast, id: Int64(lastPodcast), feed: feed(lastPodcast))
          ]
      )
      let lastEpisode = episodeCount - 1
      let episodes = try decoded.matches(
        SiriTestIntent.named(
          title(lastEpisode),
          type: .podcastEpisode,
          album: show(lastEpisode % podcastCount)
        )
      )
      #expect(episodes.map(\.identity.id) == [Int64(lastEpisode)])
      #expect(episodes.map(\.identity.feed) == [feed(lastEpisode % podcastCount)])
      let handler = SiriMediaIntentHandler(catalog: file.read, authorized: { true })
      let responses = ThreadSafe<[Int]>([])
      handler.handle(intent: try SiriTestIntent.resolved(try #require(episodes.first))) {
        response in responses { $0.append(response.code.rawValue) }
      }
      try await Wait.until({ responses().count == 1 }, { "Missing handoff callback" })
      #expect(responses() == [INPlayMediaIntentResponseCode.handleInApp.rawValue])
    }
  }

  @Test("successful reads close their descriptor and preserve the complete catalog")
  func roundTrip() async throws {
    let catalog = SiriCatalog(podcasts: [
      SiriCatalog.Podcast(
        id: 1,
        feed: "https://podcast.test/feed",
        title: "A saved show",
        episodes: [SiriCatalog.Episode(id: 2, guid: "https://podcast.test/2", title: "An episode")]
      )
    ])
    try await withFile { file in
      try file.write(catalog)
      let handle = FakeSiriCatalogReadHandle(handle: try FileHandle(forReadingFrom: file.url))
      let decoded = try await SiriCatalogFile(url: file.url, openForReading: { _ in handle }).read()
      #expect(decoded.generation == catalog.generation)
      #expect(decoded.podcasts == catalog.podcasts)
      #expect(decoded.schemaVersion == catalog.schemaVersion)
      #expect(handle.closeCount() == 1)
    }
  }

  @Test(
    "empty, invalid, and unsupported catalogs close their descriptors and cannot hand off",
    arguments: [
      "", "invalid JSON",
      "{\"schemaVersion\":1,\"generation\":\"00000000-0000-0000-0000-000000000000\",\"entries\":[]}",
      "{\"schemaVersion\":1,\"generation\":\"00000000-0000-0000-0000-000000000000\",\"podcasts\":[]}",
      "{\"schemaVersion\":3,\"generation\":\"00000000-0000-0000-0000-000000000000\",\"podcasts\":[]}",
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
      try file.write(SiriCatalog(podcasts: []))
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
    let original = SiriCatalog(podcasts: [])
    let replacement = SiriCatalog(podcasts: [])
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
