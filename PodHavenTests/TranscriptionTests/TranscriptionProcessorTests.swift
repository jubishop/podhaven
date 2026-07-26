// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Semaphore
import Testing

@testable import PodHaven

@Suite("of TranscriptionProcessor", .container)
struct TranscriptionProcessorTests {
  @Test("drains queued episodes one at a time, writing transcripts")
  func drainsQueueWritingTranscripts() async throws {
    TranscriptionHelpers.stubSpeech(
      phrases: [FakeSpeechTranscriptionResult(phrase: "hello", startSeconds: 0, endSeconds: 60)]
    )
    let repo = Container.shared.repo()
    let queue = Container.shared.transcriptionQueue()
    let processor = Container.shared.transcriptionProcessor()

    let ep1 = try await CacheHelpers.createCachedEpisode(
      title: "Episode 1",
      cachedFilename: "ep1.mp3",
      dataSize: 1
    )
    let ep2 = try await CacheHelpers.createCachedEpisode(
      title: "Episode 2",
      cachedFilename: "ep2.mp3",
      dataSize: 1
    )

    for episodeID in [ep1.id, ep2.id] {
      queue.enqueue(episodeID)
    }
    processor.handleScenePhaseChange(to: .active)

    try await Wait.until(
      { queue.episodeIDs.isEmpty },
      { "queue did not drain: \(queue.episodeIDs)" }
    )

    let segments1 = try await repo.episode(ep1.id)?.decodedTranscript?.segments
    let segments2 = try await repo.episode(ep2.id)?.decodedTranscript?.segments
    #expect(segments1?.first?.text == "hello")
    #expect(segments2?.first?.text == "hello")

    processor.handleScenePhaseChange(to: .background)
  }

  @Test("user cancellation stops the active episode and advances once")
  func userCancellationStopsActiveEpisode() async throws {
    TranscriptionHelpers.stubSpeech(
      phrases: [FakeSpeechTranscriptionResult(phrase: "done", startSeconds: 0, endSeconds: 60)]
    )
    let firstAnalysisStarted = AsyncSemaphore(value: 0)
    let firstAnalysisRelease = AsyncSemaphore(value: 0)
    let cancellationStarted = AsyncSemaphore(value: 0)
    let cancellationRelease = AsyncSemaphore(value: 0)
    let secondAnalysisStarted = AsyncSemaphore(value: 0)
    let secondAnalysisRelease = AsyncSemaphore(value: 0)
    let analyzeCount = ThreadSafe(0)
    let cancellationCount = ThreadSafe(0)
    Container.shared.speechAnalyzer.register {
      { _ in
        FakeSpeechAnalyzer(
          analyzeAudio: { _, endTime in
            let invocation = analyzeCount {
              $0 += 1
              return $0
            }
            if invocation == 1 {
              firstAnalysisStarted.signal()
              try await firstAnalysisRelease.waitUnlessCancelled()
            } else if invocation == 2 {
              secondAnalysisStarted.signal()
              try await secondAnalysisRelease.waitUnlessCancelled()
            }
            return CMTime(seconds: endTime, preferredTimescale: 600)
          },
          cancelAudio: {
            cancellationCount { $0 += 1 }
            cancellationStarted.signal()
            await cancellationRelease.wait()
          }
        )
      }
    }

    let repo = Container.shared.repo()
    let queue = Container.shared.transcriptionQueue()
    let processor = Container.shared.transcriptionProcessor()
    let firstEpisode = try await CacheHelpers.createCachedEpisode(
      title: "Cancelled",
      cachedFilename: "cancelled.mp3",
      dataSize: 1
    )
    let secondEpisode = try await CacheHelpers.createCachedEpisode(
      title: "Next",
      cachedFilename: "next.mp3",
      dataSize: 1
    )
    queue.enqueue(firstEpisode.id)
    queue.enqueue(secondEpisode.id)
    processor.handleScenePhaseChange(to: .active)
    defer {
      firstAnalysisRelease.signal()
      cancellationRelease.signal()
      secondAnalysisRelease.signal()
      processor.handleScenePhaseChange(to: .background)
    }

    await firstAnalysisStarted.wait()
    try await Wait.until(
      { queue.progress[firstEpisode.id] != nil },
      { "active transcription did not publish progress" }
    )

    processor.cancel(firstEpisode.id)
    await cancellationStarted.wait()

    #expect(queue.status(for: firstEpisode.id, hasTranscript: false) == .cancelling)
    #expect(queue.episodeIDs == [secondEpisode.id])
    #expect(analyzeCount() == 1)
    #expect(
      [Episode.ID]
        .load(
          from: Container.shared.standardDefaults(),
          forKey: "transcriptionQueue"
        ) == [secondEpisode.id]
    )

    cancellationRelease.signal()
    await secondAnalysisStarted.wait()

    #expect(queue.episodeIDs == [secondEpisode.id])
    #expect(queue.progress[firstEpisode.id] == nil)
    #expect(cancellationCount() == 1)
    #expect(analyzeCount() == 2)
    #expect(try await repo.episode(firstEpisode.id)?.hasTranscript == false)

    secondAnalysisRelease.signal()
    try await Wait.until(
      { queue.episodeIDs.isEmpty },
      { "next episode did not finish after cancellation: \(queue.episodeIDs)" }
    )
    #expect(try await repo.episode(secondEpisode.id)?.hasTranscript == true)
    #expect(analyzeCount() == 2)
  }

  @Test("late cancellation cannot affect the next active episode")
  func lateCancellationDoesNotAffectNextEpisode() async throws {
    TranscriptionHelpers.stubSpeech(
      phrases: [FakeSpeechTranscriptionResult(phrase: "done", startSeconds: 0, endSeconds: 60)]
    )
    let secondAnalysisStarted = AsyncSemaphore(value: 0)
    let secondAnalysisRelease = AsyncSemaphore(value: 0)
    let analyzeCount = ThreadSafe(0)
    Container.shared.speechAnalyzer.register {
      { _ in
        FakeSpeechAnalyzer { _, endTime in
          let invocation = analyzeCount {
            $0 += 1
            return $0
          }
          if invocation == 2 {
            secondAnalysisStarted.signal()
            try await secondAnalysisRelease.waitUnlessCancelled()
          }
          return CMTime(seconds: endTime, preferredTimescale: 600)
        }
      }
    }

    let repo = Container.shared.repo()
    let queue = Container.shared.transcriptionQueue()
    let processor = Container.shared.transcriptionProcessor()
    let firstEpisode = try await CacheHelpers.createCachedEpisode(
      title: "Completed",
      cachedFilename: "completed.mp3",
      dataSize: 1
    )
    let secondEpisode = try await CacheHelpers.createCachedEpisode(
      title: "Still active",
      cachedFilename: "still-active.mp3",
      dataSize: 1
    )
    queue.enqueue(firstEpisode.id)
    queue.enqueue(secondEpisode.id)
    processor.handleScenePhaseChange(to: .active)
    defer {
      secondAnalysisRelease.signal()
      processor.handleScenePhaseChange(to: .background)
    }

    await secondAnalysisStarted.wait()
    #expect(queue.episodeIDs == [secondEpisode.id])

    processor.cancel(firstEpisode.id)

    #expect(queue.episodeIDs == [secondEpisode.id])
    #expect(queue.progress[secondEpisode.id] != nil)
    secondAnalysisRelease.signal()

    try await Wait.until(
      { queue.episodeIDs.isEmpty },
      { "next episode did not complete: \(queue.episodeIDs)" }
    )
    #expect(try await repo.episode(firstEpisode.id)?.hasTranscript == true)
    #expect(try await repo.episode(secondEpisode.id)?.hasTranscript == true)
    #expect(analyzeCount() == 2)
  }

  @Test("an uncached episode is downloaded, awaited, then transcribed")
  func downloadsUncachedEpisodeBeforeTranscribing() async throws {
    TranscriptionHelpers.stubSpeech(
      phrases: [FakeSpeechTranscriptionResult(phrase: "hello", startSeconds: 0, endSeconds: 60)]
    )
    let repo = Container.shared.repo()
    let queue = Container.shared.transcriptionQueue()
    let processor = Container.shared.transcriptionProcessor()

    let podcastEpisode = try await Create.podcastEpisode()

    queue.enqueue(podcastEpisode.id)
    processor.handleScenePhaseChange(to: .active)

    // The processor starts the download and suspends until it completes;
    // driving the background finish must resume it without any clock advance.
    let taskID = try await CacheHelpers.waitForDownloadTask(podcastEpisode.id)
    try await CacheHelpers.waitForResumed(taskID)
    try await CacheHelpers.simulateBackgroundFinish(taskID)

    try await Wait.until(
      { queue.episodeIDs.isEmpty },
      { "queue did not drain after download finished: \(queue.episodeIDs)" }
    )

    let segments = try await repo.episode(podcastEpisode.id)?.decodedTranscript?.segments
    #expect(segments?.first?.text == "hello")

    processor.handleScenePhaseChange(to: .background)
  }

  @Test("backgrounding during an audio download preserves the foreground drain")
  func backgroundingDuringDownloadPreservesForegroundDrain() async throws {
    TranscriptionHelpers.stubSpeech(
      phrases: [FakeSpeechTranscriptionResult(phrase: "hello", startSeconds: 0, endSeconds: 60)]
    )
    let repo = Container.shared.repo()
    let queue = Container.shared.transcriptionQueue()
    let processor = Container.shared.transcriptionProcessor()
    let podcastEpisode = try await Create.podcastEpisode()

    queue.enqueue(podcastEpisode.id)
    processor.handleScenePhaseChange(to: .active)
    defer { processor.handleScenePhaseChange(to: .background) }

    let taskID = try await CacheHelpers.waitForDownloadTask(podcastEpisode.id)
    try await CacheHelpers.waitForResumed(taskID)
    #expect(queue.progress[podcastEpisode.id] == 0)

    processor.handleScenePhaseChange(to: .background)
    try await CacheHelpers.simulateBackgroundFinish(taskID)

    try await Wait.until(
      { queue.episodeIDs.isEmpty },
      { "foreground drain did not resume after the download: \(queue.episodeIDs)" }
    )
    #expect(
      try await repo.episode(podcastEpisode.id)?.decodedTranscript?.segments.first?.text == "hello"
    )
  }

  @Test("an unsupported locale fails before requesting uncached audio")
  func unsupportedLocaleFailsBeforeRequestingAudio() async throws {
    TranscriptionHelpers.stubSpeech(
      modelManager: FakeSpeechModelManager(supportedIdentifiers: [], installedIdentifiers: [])
    )
    let session = try #require(
      Container.shared.cacheManagerSession() as? FakeDataFetchable
    )
    let queue = Container.shared.transcriptionQueue()
    let processor = Container.shared.transcriptionProcessor()
    let podcastEpisode = try await Create.podcastEpisode()

    queue.enqueue(podcastEpisode.id)
    processor.handleScenePhaseChange(to: .active)
    defer { processor.handleScenePhaseChange(to: .background) }

    try await Wait.until(
      { queue.failed.contains(podcastEpisode.id) },
      { "unsupported transcription did not fail: \(queue.episodeIDs)" }
    )
    #expect(await session.downloadTasks().isEmpty)
  }

  @Test("a stranded downloading flag restarts the download before transcribing")
  func strandedDownloadingFlagRestartsDownloadBeforeTranscribing() async throws {
    TranscriptionHelpers.stubSpeech(
      phrases: [FakeSpeechTranscriptionResult(phrase: "hello", startSeconds: 0, endSeconds: 60)]
    )
    let repo = Container.shared.repo()
    let queue = Container.shared.transcriptionQueue()
    let processor = Container.shared.transcriptionProcessor()

    let podcastEpisode = try await Create.podcastEpisode()
    try await repo.updateDownloading(podcastEpisode.id, downloading: true)

    queue.enqueue(podcastEpisode.id)
    processor.handleScenePhaseChange(to: .active)
    defer { processor.handleScenePhaseChange(to: .background) }

    let taskID = try await CacheHelpers.waitForDownloadTask(podcastEpisode.id)
    try await CacheHelpers.waitForResumed(taskID)
    try await CacheHelpers.simulateBackgroundFinish(taskID)

    try await Wait.until(
      { queue.episodeIDs.isEmpty },
      { "queue did not drain after stranded download restarted: \(queue.episodeIDs)" }
    )

    let segments = try await repo.episode(podcastEpisode.id)?.decodedTranscript?.segments
    #expect(segments?.first?.text == "hello")
  }

  @Test("a failing transcription is marked failed and dequeued")
  func failureMarksFailedAndDequeues() async throws {
    TranscriptionHelpers.stubSpeechFailure()
    let repo = Container.shared.repo()
    let queue = Container.shared.transcriptionQueue()
    let processor = Container.shared.transcriptionProcessor()

    let ep = try await CacheHelpers.createCachedEpisode(
      title: "Failure",
      cachedFilename: "ep.mp3",
      dataSize: 1
    )

    queue.enqueue(ep.id)
    processor.handleScenePhaseChange(to: .active)

    try await Wait.until(
      { queue.episodeIDs.isEmpty },
      { "failed episode was not dequeued" }
    )

    #expect(queue.failed.contains(ep.id))
    let hasTranscript = try await repo.episode(ep.id)?.hasTranscript
    #expect(hasTranscript == false)

    processor.handleScenePhaseChange(to: .background)
  }

  @Test("an episode with no recognizable speech stores an empty transcript and isn't failed")
  func noSpeechStoresEmptyTranscript() async throws {
    TranscriptionHelpers.stubSpeech(phrases: [])
    let repo = Container.shared.repo()
    let queue = Container.shared.transcriptionQueue()
    let processor = Container.shared.transcriptionProcessor()

    let ep = try await CacheHelpers.createCachedEpisode(
      title: "No Speech",
      cachedFilename: "ep.mp3",
      dataSize: 1
    )

    queue.enqueue(ep.id)
    processor.handleScenePhaseChange(to: .active)

    try await Wait.until(
      { queue.episodeIDs.isEmpty },
      { "queue did not drain: \(queue.episodeIDs)" }
    )

    let episode = try await repo.episode(ep.id)
    #expect(episode?.hasTranscript == true)
    #expect(episode?.decodedTranscript?.segments.isEmpty == true)
    #expect(!queue.failed.contains(ep.id))

    processor.handleScenePhaseChange(to: .background)
  }
}
