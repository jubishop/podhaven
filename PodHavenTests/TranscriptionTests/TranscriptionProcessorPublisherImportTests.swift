// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Semaphore
import Testing

@testable import PodHaven

@Suite("of TranscriptionProcessor publisher imports", .container)
struct TranscriptionProcessorPublisherImportTests {
  @Test("publisher import wins an active on-device completion race")
  func publisherImportWinsActiveCompletionRace() async throws {
    TranscriptionHelpers.stubSpeech(
      phrases: [
        FakeSpeechTranscriptionResult(
          phrase: "on-device words",
          startSeconds: 0,
          endSeconds: 60
        )
      ]
    )
    let analysisStarted = AsyncSemaphore(value: 0)
    let analysisRelease = AsyncSemaphore(value: 0)
    let cancellationCount = ThreadSafe(0)
    Container.shared.speechAnalyzer.register {
      { _ in
        FakeSpeechAnalyzer(
          analyzeAudio: { _, endTime in
            analysisStarted.signal()
            try await analysisRelease.waitUnlessCancelled()
            return CMTime(seconds: endTime, preferredTimescale: 600)
          },
          cancelAudio: { cancellationCount { $0 += 1 } }
        )
      }
    }

    let transcriptURL = URL(string: "https://example.com/race.vtt")!
    let reference = PublisherTranscriptReference(
      url: transcriptURL,
      mimeType: "text/vtt",
      language: "en"
    )
    let fetchCount = ThreadSafe(0)
    let session = Container.shared.publisherTranscriptSession() as! FakeDataFetchable
    await session.respond(to: transcriptURL) { url in
      let invocation = fetchCount {
        $0 += 1
        return $0
      }
      let data =
        invocation == 1
        ? Data("not WebVTT".utf8)
        : Data(
          "WEBVTT\n\n00:00:02.000 --> 00:00:04.000\nPublisher wins".utf8
        )
      return (data, URL.response(url))
    }

    let repo = Container.shared.repo()
    let queue = Container.shared.transcriptionQueue()
    let processor = Container.shared.transcriptionProcessor()
    let publisherProcessor = Container.shared.publisherTranscriptProcessor()
    let episode = try await CacheHelpers.createCachedEpisode(
      title: "Publisher race",
      cachedFilename: "publisher-race.mp3",
      dataSize: 1,
      publisherTranscriptReferences: [reference]
    )
    let checkpoint = TranscriptionCheckpoint(
      segments: [TranscriptSegment(start: 0, end: 1, text: "partial")],
      audioTime: 1,
      duration: 60,
      locale: "en-US",
      audioSHA256: FakeAudioFileHasher.defaultSHA256
    )
    try await repo.saveTranscriptionCheckpoint(checkpoint, for: episode.id)
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
    try await queue.enqueue(episode.id)
    processor.handleScenePhaseChange(to: .active)
    defer {
      analysisRelease.signal()
      processor.handleScenePhaseChange(to: .background)
    }

    await analysisStarted.wait()
    await publisherProcessor.makeForegroundProgress()

    let stored = try #require(try await repo.episode(episode.id))
    #expect(stored.decodedTranscript?.segments.map(\.text) == ["Publisher wins"])
    #expect(stored.publisherTranscriptSource == reference)
    #expect(queue.episodeIDs.isEmpty)
    #expect(try await repo.transcriptionCheckpoint(episode.id) == nil)
    #expect(fetchCount() == 2)
    #expect(cancellationCount() == 1)
  }

  @Test("queued publisher preflight rejects content withdrawn while fetching")
  func queuedPublisherPreflightRejectsWithdrawnContent() async throws {
    Container.shared.speechModelManager.register {
      FakeSpeechModelManager(supportedIdentifiers: [])
    }
    let transcriptURL = URL(string: "https://example.com/withdrawn.vtt")!
    let reference = PublisherTranscriptReference(
      url: transcriptURL,
      mimeType: "text/vtt",
      language: "en"
    )
    let session = Container.shared.publisherTranscriptSession() as! FakeDataFetchable
    let fetch = await session.releaseWaitRespond(
      to: transcriptURL,
      data: Data(
        "WEBVTT\n\n00:00:00.000 --> 00:00:01.000\nWithdrawn words".utf8
      )
    )
    let repo = Container.shared.repo()
    let queue = Container.shared.transcriptionQueue()
    let processor = Container.shared.transcriptionProcessor()
    let episode = try await CacheHelpers.createCachedEpisode(
      title: "Withdrawn publisher preflight",
      cachedFilename: "withdrawn-publisher.mp3",
      dataSize: 1,
      publisherTranscriptReferences: [reference]
    )
    try await queue.enqueue(episode.id)
    processor.handleScenePhaseChange(to: .active)
    defer {
      fetch.finish.signal()
      processor.handleScenePhaseChange(to: .background)
    }

    await fetch.started.wait()
    let podcast = try #require(try await repo.podcast(episode.podcastID))
    try await repo.updateSeriesFromFeed(
      podcast: podcast,
      updatedPodcast: nil,
      unsavedEpisodes: [],
      existingEpisodes: [try Self.feedMergeEpisode(episode, references: [])]
    )
    fetch.finish.signal()

    try await Wait.until(
      { queue.episodeIDs.isEmpty },
      { "Queued publisher preflight did not finish" }
    )
    let stored = try #require(try await repo.episode(episode.id))
    #expect(stored.publisherTranscriptReferences.isEmpty)
    #expect(stored.decodedTranscript == nil)
    #expect(stored.publisherTranscriptSource == nil)
  }

  @Test("publisher preflight does not wait for feed connectivity before cached audio")
  func publisherPreflightDoesNotBlockCachedAudio() async throws {
    TranscriptionHelpers.stubSpeech(
      phrases: [
        FakeSpeechTranscriptionResult(
          phrase: "offline on-device words",
          startSeconds: 0,
          endSeconds: 60
        )
      ]
    )
    let analysisStarted = ThreadSafe(false)
    Container.shared.speechAnalyzer.register {
      { _ in
        FakeSpeechAnalyzer(
          analyzeAudio: { _, endTime in
            analysisStarted(true)
            return CMTime(seconds: endTime, preferredTimescale: 600)
          }
        )
      }
    }

    let transcriptURL = URL(string: "https://example.com/offline.vtt")!
    let reference = PublisherTranscriptReference(
      url: transcriptURL,
      mimeType: "text/vtt",
      language: "en"
    )
    let feedSession = Container.shared.podcastFeedSession() as! FakeDataFetchable
    let releaseFeedWait = await feedSession.waitRespond(
      to: transcriptURL,
      data: Data("WEBVTT\n\n00:00:00.000 --> 00:00:01.000\nPublisher".utf8)
    )
    let publisherSession = Container.shared.publisherTranscriptSession() as! FakeDataFetchable
    await publisherSession.respond(
      to: transcriptURL,
      error: URLError(.notConnectedToInternet)
    )

    let queue = Container.shared.transcriptionQueue()
    let processor = Container.shared.transcriptionProcessor()
    let episode = try await CacheHelpers.createCachedEpisode(
      title: "Offline publisher preflight",
      cachedFilename: "offline-publisher.mp3",
      dataSize: 1,
      publisherTranscriptReferences: [reference]
    )
    try await queue.enqueue(episode.id)
    processor.handleScenePhaseChange(to: .active)
    defer {
      releaseFeedWait.signal()
      processor.handleScenePhaseChange(to: .background)
    }

    try await Wait.until(
      { analysisStarted() },
      { "Cached on-device analysis never started" }
    )
    try await Wait.until(
      { queue.episodeIDs.isEmpty },
      { "Offline transcription remained queued" }
    )
    let stored = try #require(try await Container.shared.repo().episode(episode.id))
    #expect(stored.decodedTranscript?.segments.map(\.text) == ["offline on-device words"])
    #expect(await feedSession.requests.isEmpty)
    #expect(await publisherSession.requests == [transcriptURL])
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
