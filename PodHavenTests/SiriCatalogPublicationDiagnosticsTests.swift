// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of Siri catalog publication diagnostics", .container)
struct SiriCatalogPublicationDiagnosticsTests {
  private func publicationLogs(_ sink: LogCapture.Sink) -> [LogCapture.Captured] {
    sink.captured().filter { $0.message.hasPrefix("siriCatalogPublication ") }
  }

  @Test("launch summaries report open time, launch state, size limit, and slow thresholds")
  func launchSummaries() {
    let diagnostics = Container.shared.siriCatalogPublicationDiagnostics()
    diagnostics.launching(applicationState: .background)
    LogCapture.withSink { sink in
      for (open, fetch, bytes) in [
        (Duration.milliseconds(120), Duration.milliseconds(300), SiriCatalogFile.maximumBytes + 1),
        (.milliseconds(1_500), .milliseconds(1), 10),
        (.milliseconds(1), .milliseconds(1_000), 10),
        (.milliseconds(999), .milliseconds(799), SiriCatalogFile.maximumBytes),
      ] {
        diagnostics.record(
          .init(
            trigger: .launch(openDuration: open),
            fetchDuration: fetch,
            writeDuration: .milliseconds(200),
            podcasts: 2,
            episodes: 3,
            bytes: bytes
          )
        )
      }
      let logs = publicationLogs(sink)
      #expect(logs.map(\.level) == [.warning, .warning, .warning, .debug])
      #expect(
        logs.first?.message
          == "siriCatalogPublication trigger=launch publishMs=500 fetchMs=300 writeMs=200 "
          + "podcasts=2 episodes=3 bytes=33554433 maxBytes=33554432 oversized=true "
          + "openMs=120 appState=background suppressed=0"
      )
      #expect(logs.last?.message.contains("oversized=false openMs=999") == true)
    }
  }

  @Test("slow commit publications warn privately at most once per interval")
  func slowCommits() throws {
    let clock = Container.shared.fakeContinuousClock()
    clock.freeze()
    let url = Container.shared.siriCatalogFile().url
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let file = SiriCatalogFile(
      url: url,
      replaceContents: { data, url in
        if !data.isEmpty { clock.advance(by: .seconds(2)) }
        try data.write(to: url, options: .atomic)
      }
    )
    let database = Container.shared.appDB().unsafeTestDB
    database.add(transactionObserver: SiriCatalogPublisher(file: file), extent: .databaseLifetime)
    func commit(_ index: Int) throws -> [LogCapture.Captured] {
      try database.writeWithoutTransaction { db in
        try LogCapture.withSink { sink in
          try db.inTransaction {
            let podcast =
              try Create.unsavedPodcast(
                feedURL: FeedURL(URL(string: "https://private-sentinel.invalid/\(index)")!),
                title: "Private Sentinel Title \(index)"
              )
              .insertAndFetch(db, as: Podcast.self)
            _ =
              try Create.unsavedEpisode(
                podcastId: podcast.id,
                guid: GUID("private-sentinel-guid-\(index)"),
                title: "Private Sentinel Episode \(index)"
              )
              .insertAndFetch(db, as: Episode.self)
            return .commit
          }
          return publicationLogs(sink)
        }
      }
    }

    let first = try commit(1)
    #expect(first.map(\.level) == [.warning])
    let message = try #require(first.first?.message)
    #expect(
      message.hasPrefix(
        "siriCatalogPublication trigger=commit publishMs=2000 fetchMs=0 writeMs=2000 "
          + "podcasts=1 episodes=1 bytes="
      )
    )
    #expect(message.hasSuffix("oversized=false openMs=none appState=none suppressed=0"))
    #expect(message.utf8.count <= 512)
    for value in ["Private Sentinel", "private-sentinel"] {
      #expect(!message.contains(value), "Diagnostics must not include media metadata")
    }

    #expect(try commit(2).map(\.level) == [.debug])
    clock.advance(by: .seconds(15 * 60))
    let third = try commit(3)
    #expect(third.map(\.level) == [.warning])
    #expect(third.first?.message.contains("podcasts=3 episodes=3") == true)
    #expect(third.first?.message.hasSuffix("suppressed=1") == true)
  }
}
