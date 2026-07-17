// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Semaphore
import Testing

@testable import PodHaven

@Suite("of TranscriptionProcessor background task", .container)
struct TranscriptionBackgroundTaskTests {
  @Test("registering with no queued work does not schedule a background task")
  func emptyQueueDoesNotSchedule() throws {
    let processor = Container.shared.transcriptionProcessor()
    let scheduler = try #require(Container.shared.bgTaskScheduler() as? FakeBGTaskScheduler)

    processor.register()

    #expect(scheduler.submissions.isEmpty)
  }

  @Test("the iOS-granted background task drains the queue and completes")
  func backgroundTaskDrainsQueue() async throws {
    TranscriptionHelpers.stubSpeech(
      phrases: [FakeSpeechTranscriptionResult(phrase: "hi", startSeconds: 0)]
    )
    let repo = Container.shared.repo()
    let queue = Container.shared.transcriptionQueue()
    let processor = Container.shared.transcriptionProcessor()
    let scheduler = try #require(Container.shared.bgTaskScheduler() as? FakeBGTaskScheduler)

    let episode = try await CacheHelpers.createCachedEpisode(
      title: "Background",
      cachedFilename: "ep.mp3",
      dataSize: 1
    )
    queue.enqueue(episode.id)

    processor.register()
    let identifier = "\(AppInfo.bundleIdentifier).transcription"
    #expect(scheduler.pendingIdentifiers.contains(identifier))
    let task = try #require(
      scheduler.launchTask(withIdentifier: identifier)
    )

    try await Wait.until(
      { queue.episodeIDs.isEmpty },
      { "background task did not drain the queue: \(queue.episodeIDs)" }
    )

    let hasTranscript = try await repo.episode(episode.id)?.hasTranscript
    #expect(hasTranscript == true)

    try await Wait.until(
      { task.completionResults == [true] },
      { "background task did not complete successfully: \(task.completionResults)" }
    )
    #expect(!scheduler.pendingIdentifiers.contains(identifier))
  }

  @Test("a foreground drain cancels its pending background request")
  func foregroundDrainCancelsPendingRequest() async throws {
    TranscriptionHelpers.stubSpeech(
      phrases: [FakeSpeechTranscriptionResult(phrase: "hi", startSeconds: 0)]
    )
    let queue = Container.shared.transcriptionQueue()
    let processor = Container.shared.transcriptionProcessor()
    let scheduler = try #require(Container.shared.bgTaskScheduler() as? FakeBGTaskScheduler)
    let episode = try await CacheHelpers.createCachedEpisode(
      title: "Foreground",
      cachedFilename: "foreground.mp3",
      dataSize: 1
    )
    let identifier = "\(AppInfo.bundleIdentifier).transcription"

    queue.enqueue(episode.id)
    processor.register()
    #expect(scheduler.pendingIdentifiers.contains(identifier))

    processor.handleScenePhaseChange(to: .active)
    defer { processor.handleScenePhaseChange(to: .background) }

    try await Wait.until(
      { queue.episodeIDs.isEmpty },
      { "foreground task did not drain the queue: \(queue.episodeIDs)" }
    )
    #expect(!scheduler.pendingIdentifiers.contains(identifier))
  }

  @Test("foreground and background consumers never analyze the same head concurrently")
  func foregroundAndBackgroundDoNotOverlap() async throws {
    TranscriptionHelpers.stubSpeech(
      phrases: [FakeSpeechTranscriptionResult(phrase: "hi", startSeconds: 0)]
    )
    let analyzerStarted = AsyncSemaphore(value: 0)
    let analyzerRelease = AsyncSemaphore(value: 0)
    let activeAnalyzers = ThreadSafe(0)
    let maximumActiveAnalyzers = ThreadSafe(0)
    Container.shared.speechAnalyzer.register {
      { _ in
        FakeSpeechAnalyzer {
          let active = activeAnalyzers {
            $0 += 1
            return $0
          }
          maximumActiveAnalyzers { $0 = max($0, active) }
          analyzerStarted.signal()
          defer { activeAnalyzers { $0 -= 1 } }
          try await analyzerRelease.waitUnlessCancelled()
          return .zero
        }
      }
    }

    let queue = Container.shared.transcriptionQueue()
    let processor = Container.shared.transcriptionProcessor()
    let scheduler = try #require(Container.shared.bgTaskScheduler() as? FakeBGTaskScheduler)
    let episode = try await CacheHelpers.createCachedEpisode(
      title: "Exclusive drain",
      cachedFilename: "exclusive.mp3",
      dataSize: 1
    )

    queue.enqueue(episode.id)
    processor.register()
    let task = try #require(
      scheduler.launchTask(withIdentifier: "\(AppInfo.bundleIdentifier).transcription")
    )
    await analyzerStarted.wait()

    processor.handleScenePhaseChange(to: .active)

    do {
      try await Wait.until(
        maxAttempts: 100,
        delay: .milliseconds(5),
        { maximumActiveAnalyzers() > 1 },
        { "no overlapping analyzer was observed" }
      )
    } catch {
      // The timeout is the expected path once drain ownership is exclusive.
    }

    #expect(maximumActiveAnalyzers() == 1)

    analyzerRelease.signal()
    analyzerRelease.signal()
    try await Wait.until(
      { queue.episodeIDs.isEmpty },
      { "queue did not drain: \(queue.episodeIDs)" }
    )
    try await Wait.until(
      { task.completionResults == [true] },
      { "background task did not complete: \(task.completionResults)" }
    )

    processor.handleScenePhaseChange(to: .background)
  }

  @Test("a brief background transition preserves the in-flight foreground transcription")
  func backgroundTransitionPreservesInFlightForegroundTranscription() async throws {
    TranscriptionHelpers.stubSpeech(
      phrases: [
        FakeSpeechTranscriptionResult(
          phrase: "preserved",
          startSeconds: 0,
          endSeconds: 50
        )
      ],
      durationSeconds: 100
    )
    let analyzerStarted = AsyncSemaphore(value: 0)
    let analyzerRelease = AsyncSemaphore(value: 0)
    let analyzeCount = ThreadSafe(0)
    Container.shared.speechAnalyzer.register {
      { _ in
        FakeSpeechAnalyzer(durationSeconds: 100) {
          analyzeCount { $0 += 1 }
          analyzerStarted.signal()
          try await analyzerRelease.waitUnlessCancelled()
          return .zero
        }
      }
    }

    let repo = Container.shared.repo()
    let queue = Container.shared.transcriptionQueue()
    let processor = Container.shared.transcriptionProcessor()
    let episode = try await CacheHelpers.createCachedEpisode(
      title: "Foreground lifecycle",
      cachedFilename: "foreground-lifecycle.mp3",
      dataSize: 1
    )
    queue.enqueue(episode.id)

    processor.handleScenePhaseChange(to: .active)
    await analyzerStarted.wait()
    try await Wait.until(
      { queue.progress[episode.id] == 0.5 },
      { "transcription did not report progress: \(queue.progress)" }
    )

    processor.handleScenePhaseChange(to: .background)
    processor.handleScenePhaseChange(to: .active)

    do {
      try await Wait.until(
        maxAttempts: 100,
        delay: .milliseconds(5),
        { analyzeCount() > 1 },
        { "transcription was not restarted" }
      )
    } catch {
      // The timeout is expected when the in-flight analyzer is preserved.
    }

    #expect(analyzeCount() == 1)
    #expect(queue.progress[episode.id] == 0.5)

    analyzerRelease.signal()
    try await Wait.until(
      { queue.episodeIDs.isEmpty },
      { "queue did not drain: \(queue.episodeIDs)" }
    )
    #expect(
      try await repo.episode(episode.id)?.decodedTranscript?.segments.first?.text == "preserved"
    )

    processor.handleScenePhaseChange(to: .background)
  }

  @Test("a background grant takes the remaining queue after the foreground head finishes")
  func backgroundGrantTakesRemainingQueueAfterForegroundHead() async throws {
    TranscriptionHelpers.stubSpeech(
      phrases: [FakeSpeechTranscriptionResult(phrase: "done", startSeconds: 0)]
    )
    let firstAnalyzerStarted = AsyncSemaphore(value: 0)
    let firstAnalyzerRelease = AsyncSemaphore(value: 0)
    let analyzeCount = ThreadSafe(0)
    Container.shared.speechAnalyzer.register {
      { _ in
        FakeSpeechAnalyzer {
          let count = analyzeCount {
            $0 += 1
            return $0
          }
          guard count == 1 else { return .zero }
          firstAnalyzerStarted.signal()
          try await firstAnalyzerRelease.waitUnlessCancelled()
          return .zero
        }
      }
    }

    let repo = Container.shared.repo()
    let queue = Container.shared.transcriptionQueue()
    let processor = Container.shared.transcriptionProcessor()
    let scheduler = try #require(Container.shared.bgTaskScheduler() as? FakeBGTaskScheduler)
    let firstEpisode = try await CacheHelpers.createCachedEpisode(
      title: "Foreground head",
      cachedFilename: "foreground-head.mp3",
      dataSize: 1
    )
    let secondEpisode = try await CacheHelpers.createCachedEpisode(
      title: "Background remainder",
      cachedFilename: "background-remainder.mp3",
      dataSize: 1
    )
    queue.enqueue(firstEpisode.id)
    queue.enqueue(secondEpisode.id)

    processor.register()
    processor.handleScenePhaseChange(to: .active)
    await firstAnalyzerStarted.wait()
    processor.handleScenePhaseChange(to: .background)
    let task = try #require(
      scheduler.launchTask(withIdentifier: "\(AppInfo.bundleIdentifier).transcription")
    )

    firstAnalyzerRelease.signal()
    try await Wait.until(
      { queue.episodeIDs.isEmpty },
      { "background task did not drain the remaining queue: \(queue.episodeIDs)" }
    )
    try await Wait.until(
      { task.completionResults == [true] },
      { "background task did not complete: \(task.completionResults)" }
    )

    #expect(analyzeCount() == 2)
    #expect(try await repo.episode(firstEpisode.id)?.hasTranscript == true)
    #expect(try await repo.episode(secondEpisode.id)?.hasTranscript == true)
  }

  @Test("expiration retains the head for the next foreground drain")
  func expirationRetainsHeadForForeground() async throws {
    TranscriptionHelpers.stubSpeech(
      phrases: [FakeSpeechTranscriptionResult(phrase: "resumed", startSeconds: 0)]
    )
    let analyzerStarted = AsyncSemaphore(value: 0)
    let neverSignals = AsyncSemaphore(value: 0)
    let analyzeCount = ThreadSafe(0)
    Container.shared.speechAnalyzer.register {
      { _ in
        FakeSpeechAnalyzer {
          let count = analyzeCount {
            $0 += 1
            return $0
          }
          guard count == 1 else { return .zero }
          analyzerStarted.signal()
          try await neverSignals.waitUnlessCancelled()
          return .zero
        }
      }
    }

    let repo = Container.shared.repo()
    let queue = Container.shared.transcriptionQueue()
    let processor = Container.shared.transcriptionProcessor()
    let scheduler = try #require(Container.shared.bgTaskScheduler() as? FakeBGTaskScheduler)
    let episode = try await CacheHelpers.createCachedEpisode(
      title: "Expiring background task",
      cachedFilename: "expiry.mp3",
      dataSize: 1
    )
    queue.enqueue(episode.id)

    processor.register()
    let task = try #require(
      scheduler.launchTask(withIdentifier: "\(AppInfo.bundleIdentifier).transcription")
    )
    await analyzerStarted.wait()
    #expect(queue.progress[episode.id] != nil)

    task.expire()

    try await Wait.until(
      { task.completionResults == [false] },
      { "expired task did not complete unsuccessfully: \(task.completionResults)" }
    )
    try await Wait.until(
      { queue.progress[episode.id] == nil },
      { "expired task did not clear progress: \(queue.progress)" }
    )
    #expect(queue.episodeIDs == [episode.id])

    processor.handleScenePhaseChange(to: .active)
    try await Wait.until(
      { queue.episodeIDs.isEmpty },
      { "foreground drain did not resume the retained head: \(queue.episodeIDs)" }
    )
    #expect(
      try await repo.episode(episode.id)?.decodedTranscript?.segments.first?.text == "resumed"
    )

    processor.handleScenePhaseChange(to: .background)
  }
}
