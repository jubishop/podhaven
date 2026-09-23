// Copyright Justin Bishop, 2026

import FactoryTesting
import Foundation
import Intents
import Testing

@testable import PodHaven

@Suite("of large Siri catalogs", .container)
struct SiriLargeCatalogTests {
  @Test("large Unicode catalogs complete within budget with stable ranking and album filtering")
  @MainActor func largeCatalog() async throws {
    let entries = (0..<100_100)
      .map { i in
        SiriCatalog.Entry(
          identity: .init(
            kind: .episode,
            id: Int64(i),
            feed: "https://synthetic.test/\(i / 1000)",
            guid: "\(i)"
          ),
          title: i % 1000 == 0
            ? "Café — Ｓcience " + String(repeating: "long ", count: 200)
            : "Episode \(i) Science Today",
          podcastTitle: "Café show \(i / 1000)"
        )
      }
    let catalog = SiriCatalog(entries: entries)
    let url = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let file = SiriCatalogFile(url: url)
    try file.write(catalog)
    for (mode, name, type, album, count) in [
      ("unknown", "Episode 501 Science Today", INMediaItemType.unknown, nil, 1),
      ("episode", "Episode 501 Science Today", .podcastEpisode, nil, 1),
      ("album", "Episode 501 Science Today", .podcastEpisode, "Cafe show 0", 1),
      ("wrong-album", "Episode 501 Science Today", .podcastEpisode, "Cafe show 99", 0),
      ("no-match", "Absent", .unknown, nil, 0),
      ("unicode-ambiguous", "cafe science", .unknown, nil, 101),
    ] {
      let intent = SiriTestIntent.named(name, type: type, album: album)
      if count == 0 {
        #expect(throws: SiriMediaFailure.noMatch) { try catalog.matches(intent) }
      } else {
        let matches = try catalog.matches(intent)
        #expect(matches.count == count)
        #expect(matches.map(\.identity.id) == matches.map(\.identity.id).sorted())
      }
      let summaries = ThreadSafe<[SiriResolutionOperation.Summary]>([])
      let handler = SiriMediaIntentHandler(
        catalog: file.read,
        authorized: { true },
        diagnostic: { summary in summaries { $0.append(summary) } }
      )
      let started = ContinuousClock.now
      let callbackDuration = ThreadSafe<Duration?>(nil)
      await withCheckedContinuation { continuation in
        handler.resolveMediaItems(for: intent) { _ in
          callbackDuration(ContinuousClock.now - started)
          continuation.resume()
        }
      }
      #expect(
        try #require(callbackDuration()) < .seconds(5),
        "Siri callback completion exceeded its budget"
      )
      let summary = try #require(summaries().last)
      #expect(summary.phase == .finished)
      #expect(summary.entries == 100_100)
      #expect(summary.maxTitleBytes > 1000)
      #expect(!summary.workerMainThread)
      #expect(summary.outcome == (count == 0 ? "noMatch" : count == 1 ? "unique" : "ambiguous"))
      #expect(summary.totalMs < 5_000, "Synthetic completion budget exceeded for \(mode)")
      print(
        "Siri large catalog mode=\(mode) readMs=\(summary.readMs) decodeMs=\(summary.decodeMs) matchMs=\(summary.matchMs) totalMs=\(summary.totalMs)"
      )
    }
  }

  @Test(
    "normalization preserves the Foundation Unicode contract",
    arguments: [
      " CAFE---science! ", "Café — Ｓcience", "İstanbul Straße Æther", "中文、１２３", "a\u{301}e\u{308}",
      "👩🏽‍🔬 Science\nToday\t2", "e\u{200d}x", "\u{0301}", "𐐀 𐐨", "¼¹²Ⅲ", "\0space",
    ]
  )
  func unicode(_ name: String) {
    let expected =
      name.folding(
        options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
        locale: Locale(identifier: "en_US_POSIX")
      )
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { !$0.isEmpty }.joined(separator: " ")
    #expect(SiriCatalog.normalize(name) == expected)
  }
}
