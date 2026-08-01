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
    let session = Container.shared.podcastFeedSession() as! FakeDataFetchable
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
    try await queue.enqueue(episode.id)
    processor.handleScenePhaseChange(to: .active)
    defer {
      analysisRelease.signal()
      processor.handleScenePhaseChange(to: .background)
    }

    await analysisStarted.wait()
    #expect(await processor.importPublisherTranscript(for: episode.id))

    let stored = try #require(try await repo.episode(episode.id))
    #expect(stored.decodedTranscript?.segments.map(\.text) == ["Publisher wins"])
    #expect(stored.publisherTranscriptSource == reference)
    #expect(queue.episodeIDs.isEmpty)
    #expect(try await repo.transcriptionCheckpoint(episode.id) == nil)
    #expect(fetchCount() == 2)
    #expect(cancellationCount() == 1)
  }
}
