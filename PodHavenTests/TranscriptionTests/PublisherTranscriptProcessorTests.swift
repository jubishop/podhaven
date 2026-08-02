// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("of PublisherTranscriptProcessor", .container)
struct PublisherTranscriptProcessorTests {
  enum StaleFailure: Sendable {
    case terminal
    case finalRetry
  }

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

  @Test("removed references win over an in-flight publisher success")
  func removedReferencesWinOverInFlightSuccess() async throws {
    let oldURL = URL(string: "https://example.com/removed-in-flight.vtt")!
    let oldReference = PublisherTranscriptReference(
      url: oldURL,
      mimeType: "text/vtt",
      language: "en"
    )
    let repo = Container.shared.repo()
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(
            title: "Removed in-flight publisher demand",
            publisherTranscriptReferences: [oldReference]
          )
        ]
      )
    )
    let episode = try #require(series.episodes.first)
    let now = Date(timeIntervalSince1970: 1_000)
    Container.shared.fakeDate().freeze(at: now)
    try await Container.shared.appDB().writer
      .write { db in
        try PublisherTranscriptImportJob(
          episodeId: episode.id,
          nextAttemptAt: now
        )
        .insert(db)
      }
    let session = Container.shared.publisherTranscriptSession() as! FakeDataFetchable
    let fetch = await session.releaseWaitRespond(
      to: oldURL,
      data: Data(
        "WEBVTT\n\n00:00:00.000 --> 00:00:01.000\nWithdrawn words".utf8
      )
    )
    let processor = Container.shared.publisherTranscriptProcessor()
    let drain = Task { await processor.makeForegroundProgress() }
    defer {
      drain.cancel()
      fetch.finish.signal()
    }

    await fetch.started.wait()
    _ = try await repo.updateSeriesFromFeed(
      podcast: series.podcast,
      updatedPodcast: nil,
      unsavedEpisodes: [],
      existingEpisodes: [try Self.feedMergeEpisode(episode, references: [])]
    )

    let clearedJobCount = try await repo.db.read { db in
      try PublisherTranscriptImportJob.fetchCount(db)
    }
    #expect(clearedJobCount == 0)
    fetch.finish.signal()
    await drain.value

    let stored = try #require(try await repo.episode(episode.id))
    #expect(stored.publisherTranscriptReferences.isEmpty)
    #expect(stored.decodedTranscript == nil)
    #expect(stored.publisherTranscriptSource == nil)
  }

  @Test(
    "replacement demand survives an in-flight stale failure",
    arguments: [StaleFailure.terminal, StaleFailure.finalRetry]
  )
  func replacementDemandSurvivesStaleFailure(_ failure: StaleFailure) async throws {
    let oldURL = URL(string: "https://example.com/stale-failure.vtt")!
    let newURL = URL(string: "https://example.com/replacement.vtt")!
    let oldReference = PublisherTranscriptReference(
      url: oldURL,
      mimeType: "text/vtt",
      language: "en"
    )
    let newReference = PublisherTranscriptReference(
      url: newURL,
      mimeType: "text/vtt",
      language: "en"
    )
    let repo = Container.shared.repo()
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(
            title: "Replacement publisher demand",
            publisherTranscriptReferences: [oldReference]
          )
        ]
      )
    )
    let episode = try #require(series.episodes.first)
    let now = Date(timeIntervalSince1970: 1_000)
    Container.shared.fakeDate().freeze(at: now)
    let attemptCount =
      switch failure {
      case .terminal: 0
      case .finalRetry: PublisherTranscriptImportStore.maximumAttemptCount - 1
      }
    try await Container.shared.appDB().writer
      .write { db in
        try PublisherTranscriptImportJob(
          episodeId: episode.id,
          attemptCount: attemptCount,
          nextAttemptAt: now
        )
        .insert(db)
      }
    let session = Container.shared.publisherTranscriptSession() as! FakeDataFetchable
    let fetch =
      switch failure {
      case .terminal:
        await session.releaseWaitRespond(
          to: oldURL,
          data: Data("not a timed transcript".utf8)
        )
      case .finalRetry:
        await session.releaseWaitRespond(
          to: oldURL,
          error: URLError(.notConnectedToInternet)
        )
      }
    await session.respond(
      to: newURL,
      data: Data(
        "WEBVTT\n\n00:00:00.000 --> 00:00:01.000\nReplacement words".utf8
      )
    )
    let processor = Container.shared.publisherTranscriptProcessor()
    let staleDrain = Task { await processor.makeForegroundProgress() }
    defer {
      staleDrain.cancel()
      fetch.finish.signal()
    }

    await fetch.started.wait()
    _ = try await repo.updateSeriesFromFeed(
      podcast: series.podcast,
      updatedPodcast: nil,
      unsavedEpisodes: [],
      existingEpisodes: [try Self.feedMergeEpisode(episode, references: [newReference])]
    )
    let replacementDrain = Task { await processor.makeForegroundProgress() }
    defer { replacementDrain.cancel() }

    fetch.finish.signal()
    await staleDrain.value
    await replacementDrain.value

    let stored = try #require(try await repo.episode(episode.id))
    #expect(stored.decodedTranscript?.segments.map(\.text) == ["Replacement words"])
    #expect(stored.publisherTranscriptSource == newReference)
    #expect(await session.requests.filter { $0 == oldURL }.count == 1)
    #expect(await session.requests.filter { $0 == newURL }.count == 1)
    let jobCount = try await repo.db.read { db in
      try PublisherTranscriptImportJob.fetchCount(db)
    }
    #expect(jobCount == 0)
  }

  private static func feedMergeEpisode(
    _ episode: Episode,
    references: [PublisherTranscriptReference]
  ) throws -> FeedMergeEpisode {
    FeedMergeEpisode(
      id: episode.id,
      from: try Create.unsavedEpisode(
        guid: episode.guid,
        mediaURL: episode.mediaURL,
        title: episode.title,
        pubDate: episode.pubDate,
        duration: episode.duration,
        description: episode.description,
        link: episode.link,
        image: episode.image,
        publisherTranscriptReferences: references
      )
    )
  }
}
