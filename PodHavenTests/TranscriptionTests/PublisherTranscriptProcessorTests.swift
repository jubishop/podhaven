// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("of PublisherTranscriptProcessor", .container)
struct PublisherTranscriptProcessorTests {
  @Test("persisted demand schedules a network task and drains without speech support")
  func persistedDemandSchedulesNetworkTaskWithoutSpeechSupport() async throws {
    Container.shared.speechModelManager.register {
      FakeSpeechModelManager(supportedIdentifiers: [])
    }
    let availability = Container.shared.transcriptionAvailability()
    await availability.prepare()
    #expect(availability.state == .unavailable)

    let transcriptURL = URL(string: "https://example.com/persisted-publisher.vtt")!
    let reference = PublisherTranscriptReference(
      url: transcriptURL,
      mimeType: "text/vtt",
      language: "en"
    )
    let repo = Container.shared.repo()
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(
            title: "Persisted publisher demand",
            publisherTranscriptReferences: [reference]
          )
        ]
      )
    )
    let episode = try #require(series.episodes.first)
    let now = Date(timeIntervalSince1970: 1_000)
    Container.shared.fakeDate().freeze(at: now)
    try await Container.shared.appDB().writer
      .write { db in
        try PublisherTranscriptImportStore.insert(
          episode.id,
          nextAttemptAt: now,
          in: db
        )
      }
    let session = Container.shared.publisherTranscriptSession() as! FakeDataFetchable
    await session.respond(
      to: transcriptURL,
      data: Data(
        "WEBVTT\n\n00:00:00.000 --> 00:00:01.000\nPersisted publisher words".utf8
      )
    )
    let queue = Container.shared.transcriptionQueue()
    await queue.waitUntilLoaded()
    let scheduler = try #require(
      Container.shared.bgTaskScheduler() as? FakeBGTaskScheduler
    )
    let processor = Container.shared.publisherTranscriptProcessor()
    let identifier = "\(AppInfo.bundleIdentifier).publisherTranscripts"

    processor.register()

    try await Wait.until(
      { scheduler.pendingIdentifiers.contains(identifier) },
      { "Persisted publisher demand did not schedule background work" }
    )
    let request = try #require(
      scheduler.submissions.last { $0.identifier == identifier }
    )
    #expect(request.isProcessing)
    #expect(request.requiresNetworkConnectivity)
    let task = try #require(scheduler.launchTask(withIdentifier: identifier))

    try await Wait.until(
      { task.completionResults == [true] },
      { "Persisted publisher background task did not complete successfully" }
    )

    let stored = try #require(try await repo.episode(episode.id))
    #expect(stored.decodedTranscript?.segments.map(\.text) == ["Persisted publisher words"])
    #expect(stored.publisherTranscriptSource == reference)
    #expect(queue.episodeIDs.isEmpty)
    let jobCount = try await repo.db.read { db in
      try PublisherTranscriptImportJob.fetchCount(db)
    }
    #expect(jobCount == 0)
  }
}
