// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import GRDB
import Semaphore
import Testing

@testable import PodHaven

@Suite("of TranscriptionProcessor publisher replacements", .container)
struct TranscriptionProcessorReplacementTests {
  private func insertForcedReplacement(_ episodeID: Episode.ID) async throws {
    try await Container.shared.appDB().unsafeTestDB
      .write { db in
        try db.execute(
          sql: """
            INSERT INTO episodeTranscriptionQueue (episodeId, workMode)
            VALUES (?, 'onDeviceReplacement')
            """,
          arguments: [episodeID]
        )
      }
    Container.shared.transcriptionQueue.reset(.scope)
    Container.shared.transcriptionProcessor.reset(.scope)
  }

  private func storePublisherTranscript(
    for episodeID: Episode.ID,
    source: PublisherTranscriptReference,
    text: String = "Publisher words"
  ) async throws -> Transcript {
    let transcript = Transcript(
      segments: [TranscriptSegment(start: 0, end: 1, text: text)],
      locale: "en-US",
      createdAt: Date(timeIntervalSince1970: 0)
    )
    #expect(
      try await Container.shared.repo()
        .storeTranscriptIfAbsent(
          episodeID,
          transcript: transcript,
          publisherSource: source
        )
    )
    return transcript
  }

  @Test("queue reorder preserves forced replacement intent")
  func reorderPreservesReplacementIntent() async throws {
    let replacementEpisode = try await Create.podcastEpisode()
    let ordinaryEpisode = try await Create.podcastEpisode()
    try await insertForcedReplacement(replacementEpisode.id)
    let queue = Container.shared.transcriptionQueue()
    await queue.waitUntilLoaded()
    try await queue.enqueue(ordinaryEpisode.id)

    #expect(
      try await queue.reorder([ordinaryEpisode.id, replacementEpisode.id])
    )

    let workMode = try await Container.shared.appDB().unsafeTestDB
      .read { db in
        try String.fetchOne(
          db,
          sql: """
            SELECT workMode
            FROM episodeTranscriptionQueue
            WHERE episodeId = ?
            """,
          arguments: [replacementEpisode.id]
        )
      }
    #expect(workMode == "onDeviceReplacement")
  }

  @Test("forced replacement bypasses publisher preflight and transitions the observed source")
  @MainActor func forcedReplacementBypassesPublisherAndTransitionsSource() async throws {
    let replacementText = "Fresh on-device words"
    TranscriptionHelpers.stubSpeech(
      phrases: [
        FakeSpeechTranscriptionResult(
          phrase: replacementText,
          startSeconds: 0,
          endSeconds: 60
        )
      ]
    )
    let analysisCount = ThreadSafe(0)
    Container.shared.speechAnalyzer.register {
      { _ in
        FakeSpeechAnalyzer(
          analyzeAudio: { _, endTime in
            analysisCount { $0 += 1 }
            return CMTime(seconds: endTime, preferredTimescale: 600)
          }
        )
      }
    }

    let transcriptURL = URL(string: "https://example.com/replacement.vtt")!
    let source = PublisherTranscriptReference(
      url: transcriptURL,
      mimeType: "text/vtt",
      language: "en-US"
    )
    let episode = try await CacheHelpers.createCachedEpisode(
      title: "Publisher replacement",
      cachedFilename: "publisher-replacement.mp3",
      dataSize: 1,
      publisherTranscriptReferences: [source]
    )
    let originalTranscript = try await storePublisherTranscript(
      for: episode.id,
      source: source
    )
    let loaded = try #require(try await Container.shared.repo().podcastEpisode(episode.id))
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(loaded))
    viewModel.appear()
    defer { viewModel.disappear() }

    try await insertForcedReplacement(episode.id)
    let queue = Container.shared.transcriptionQueue()
    await queue.waitUntilLoaded()
    #expect(queue.episodeIDs == [episode.id])
    let processor = Container.shared.transcriptionProcessor()
    processor.handleScenePhaseChange(to: .active)
    defer { processor.handleScenePhaseChange(to: .background) }

    try await Wait.until(
      { queue.episodeIDs.isEmpty },
      { "Forced replacement did not drain" }
    )
    try await Wait.until(
      { @MainActor in
        viewModel.decodedTranscript?.segments.map(\.text) == [replacementText]
      },
      { @MainActor in
        "Expected observed on-device replacement, got \(String(describing: viewModel.decodedTranscript))"
      }
    )

    let stored = try #require(try await Container.shared.repo().episode(episode.id))
    #expect(stored.decodedTranscript != originalTranscript)
    #expect(stored.decodedTranscript?.segments.map(\.text) == [replacementText])
    #expect(stored.publisherTranscriptSource == nil)
    #expect(analysisCount() == 1)
    let publisherSession = Container.shared.publisherTranscriptSession() as! FakeDataFetchable
    #expect(await publisherSession.requests.isEmpty)
    #expect(try await Container.shared.repo().transcriptionCheckpoint(episode.id) == nil)
  }

  @Test("failed forced replacement preserves publisher transcript and exposes retry")
  @MainActor func failedReplacementPreservesPublisherTranscript() async throws {
    TranscriptionHelpers.stubSpeechFailure()
    let source = PublisherTranscriptReference(
      url: URL(string: "https://example.com/failing-replacement.vtt")!,
      mimeType: "text/vtt",
      language: "en-US"
    )
    let episode = try await CacheHelpers.createCachedEpisode(
      title: "Failing publisher replacement",
      cachedFilename: "failing-publisher-replacement.mp3",
      dataSize: 1,
      publisherTranscriptReferences: [source]
    )
    let originalTranscript = try await storePublisherTranscript(
      for: episode.id,
      source: source
    )
    try await insertForcedReplacement(episode.id)
    let queue = Container.shared.transcriptionQueue()
    await queue.waitUntilLoaded()
    let processor = Container.shared.transcriptionProcessor()
    processor.handleScenePhaseChange(to: .active)
    defer { processor.handleScenePhaseChange(to: .background) }

    try await Wait.until(
      { queue.episodeIDs.isEmpty },
      { "Failed replacement remained queued" }
    )

    let stored = try #require(try await Container.shared.repo().episode(episode.id))
    #expect(stored.decodedTranscript == originalTranscript)
    #expect(stored.publisherTranscriptSource == source)
    #expect(queue.failed.contains(episode.id))
    let loaded = try #require(try await Container.shared.repo().podcastEpisode(episode.id))
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(loaded))
    #expect(viewModel.transcriptionStatus == .failed)
  }

  @Test("pausing forced replacement preserves publisher transcript")
  func pausingReplacementPreservesPublisherTranscript() async throws {
    TranscriptionHelpers.stubSpeech(
      phrases: [
        FakeSpeechTranscriptionResult(
          phrase: "Cancelled replacement",
          startSeconds: 0,
          endSeconds: 60
        )
      ]
    )
    let analysisStarted = ThreadSafe(false)
    let analysisRelease = AsyncSemaphore(value: 0)
    Container.shared.speechAnalyzer.register {
      { _ in
        FakeSpeechAnalyzer(
          analyzeAudio: { _, endTime in
            analysisStarted(true)
            try await analysisRelease.waitUnlessCancelled()
            return CMTime(seconds: endTime, preferredTimescale: 600)
          }
        )
      }
    }
    let source = PublisherTranscriptReference(
      url: URL(string: "https://example.com/paused-replacement.vtt")!,
      mimeType: "text/vtt",
      language: "en-US"
    )
    let episode = try await CacheHelpers.createCachedEpisode(
      title: "Paused publisher replacement",
      cachedFilename: "paused-publisher-replacement.mp3",
      dataSize: 1
    )
    let originalTranscript = try await storePublisherTranscript(
      for: episode.id,
      source: source
    )
    try await insertForcedReplacement(episode.id)
    let queue = Container.shared.transcriptionQueue()
    await queue.waitUntilLoaded()
    let processor = Container.shared.transcriptionProcessor()
    processor.handleScenePhaseChange(to: .active)
    defer {
      analysisRelease.signal()
      processor.handleScenePhaseChange(to: .background)
    }

    try await Wait.until(
      { analysisStarted() },
      { "Forced replacement never began on-device analysis" }
    )
    try await processor.pause(episode.id)
    try await Wait.until(
      {
        queue.episodeIDs.isEmpty
          && queue.interruptions[episode.id] == nil
          && queue.progress[episode.id] == nil
      },
      { "Forced replacement did not finish pausing" }
    )

    let stored = try #require(try await Container.shared.repo().episode(episode.id))
    #expect(stored.decodedTranscript == originalTranscript)
    #expect(stored.publisherTranscriptSource == source)
    #expect(!queue.failed.contains(episode.id))
  }
}
