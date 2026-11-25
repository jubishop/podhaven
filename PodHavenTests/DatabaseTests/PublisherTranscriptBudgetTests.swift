// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Logging
import Testing

@testable import PodHaven

@Suite("of the publisher transcript storage budget", .container)
@MainActor struct PublisherTranscriptBudgetTests {
  @DynamicInjected(\.appDB) private var appDB
  @DynamicInjected(\.databaseMaintainer) private var databaseMaintainer
  @DynamicInjected(\.fakeDate) private var fakeDate
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.uiApplication) private var uiApplication

  private var fakeApplication: FakeApplication {
    uiApplication as! FakeApplication
  }
  private var fakeRepo: FakeRepo {
    repo as! FakeRepo
  }

  @Test("measures the UTF-8 bytes of publisher-sourced transcripts only")
  func measuresPublisherTranscriptBytes() async throws {
    let (publisherEpisode, onDeviceEpisode, _) = try await Create.threePodcastEpisodes()
    #expect(
      try await repo.storeTranscriptIfAbsent(
        publisherEpisode.id,
        transcript: makeTranscript("Café crème ☕️"),
        publisherSource: PublisherTranscriptReference(
          url: URL(string: "https://example.com/budget.json")!,
          mimeType: "application/json",
          language: "fr"
        )
      )
    )
    #expect(
      try await repo.storeTranscriptIfAbsent(
        onDeviceEpisode.id,
        transcript: makeTranscript("On-device words"),
        publisherSource: nil
      )
    )

    let storedJSON = try #require(
      try await appDB.reader.read { db in
        try Episode
          .withID(publisherEpisode.id)
          .select(Episode.Columns.transcript, as: String.self)
          .fetchOne(db)
      }
    )
    #expect(storedJSON.utf8.count > storedJSON.count)
    #expect(try await repo.publisherTranscriptByteCount() == storedJSON.utf8.count)
  }

  @Test("backgrounding over the budget logs one warning a day")
  func overBudgetWarnsOncePerDay() async throws {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    fakeDate.freeze(at: start)
    fakeRepo.publisherTranscriptByteCountOverride(
      DatabaseMaintainer.publisherTranscriptByteBudget + 1
    )

    try await LogCapture.withSink { sink in
      try await background(expectingTaskCount: 1)
      #expect(budgetWarnings(in: sink).count == 1)

      try await background(expectingTaskCount: 2)
      Container.shared.databaseMaintainer.reset(.scope)
      try await background(expectingTaskCount: 3)
      #expect(budgetWarnings(in: sink).count == 1)

      fakeDate.freeze(at: start.addingTimeInterval(24 * 60 * 60))
      try await background(expectingTaskCount: 4)
      #expect(budgetWarnings(in: sink).count == 2)
    }
  }

  @Test("backgrounding at the budget logs no warning")
  func atBudgetDoesNotWarn() async throws {
    fakeRepo.publisherTranscriptByteCountOverride(DatabaseMaintainer.publisherTranscriptByteBudget)

    try await LogCapture.withSink { sink in
      try await background(expectingTaskCount: 1)
      #expect(budgetWarnings(in: sink).isEmpty)
    }
  }

  // MARK: - Helpers

  private func makeTranscript(_ text: String) -> Transcript {
    Transcript(
      segments: [TranscriptSegment(start: 0, end: 1, text: text)],
      locale: "en-US",
      createdAt: Date(timeIntervalSince1970: 0)
    )
  }

  private func background(expectingTaskCount expectedCount: Int) async throws {
    databaseMaintainer.handleScenePhaseChange(to: .background)
    let fakeApplication = fakeApplication
    try await Wait.until(
      { @MainActor in
        let identifiers = fakeApplication.taskIdentifiers(named: "databaseMaintenance")
        return identifiers.count == expectedCount
          && identifiers.allSatisfy { fakeApplication.endCallCount(for: $0) == 1 }
      },
      { @MainActor in "Expected \(expectedCount) finished database maintenance tasks" }
    )
  }

  private func budgetWarnings(in sink: LogCapture.Sink) -> [LogCapture.Captured] {
    sink.captured()
      .filter { $0.level == .warning && $0.message.contains("transcript storage budget") }
  }
}
