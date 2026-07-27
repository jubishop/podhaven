// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Semaphore
import Testing

@testable import PodHaven

@Suite("of TranscriptionProcessor background task", .container)
struct TranscriptionBackgroundTaskTests {
  enum RemovalFailureScenario: CaseIterable, Sendable {
    case completedTranscription
    case failedTranscription
  }

  @Test("registering with no queued work does not schedule a background task")
  func emptyQueueDoesNotSchedule() throws {
    let processor = Container.shared.transcriptionProcessor()
    let scheduler = try #require(Container.shared.bgTaskScheduler() as? FakeBGTaskScheduler)

    processor.register()

    #expect(scheduler.submissions.isEmpty)
  }

  @Test("the iOS-granted background task drains the queue and completes")
  func backgroundTaskDrainsQueue() async throws {
    try await LogCapture.withSink { sink in
      TranscriptionHelpers.stubSpeech(
        phrases: [FakeSpeechTranscriptionResult(phrase: "hi", startSeconds: 0, endSeconds: 60)]
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
      try await queue.enqueue(episode.id)

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

      let messages = sink.captured().map(\.message)
      #expect(
        messages.contains {
          $0.contains("event=checkpointPersisted")
            && $0.contains("mode=background")
            && $0.contains("episodeID=\(episode.id)")
            && $0.contains("committedAudioSeconds=60.0")
        }
      )
      #expect(
        messages.contains {
          $0.contains("event=backgroundRunCompleted")
            && $0.contains("remainingEpisodes=0")
        }
      )
    }
  }

  @Test(
    "a queue removal failure ends the background grant and retains work",
    arguments: RemovalFailureScenario.allCases
  )
  func queueRemovalFailureEndsBackgroundGrant(
    _ scenario: RemovalFailureScenario
  ) async throws {
    switch scenario {
    case .completedTranscription:
      TranscriptionHelpers.stubSpeech(
        phrases: [
          FakeSpeechTranscriptionResult(
            phrase: "retained",
            startSeconds: 0,
            endSeconds: 60
          )
        ]
      )
    case .failedTranscription:
      TranscriptionHelpers.stubSpeechFailure()
    }

    let repo = Container.shared.repo()
    let episode = try await CacheHelpers.createCachedEpisode(
      title: "Retained background work",
      cachedFilename: "retained-background.mp3",
      dataSize: 1
    )
    let removalAttempts = ThreadSafe(0)
    let store = FakeTranscriptionQueueStore(
      episodeIDs: [episode.id],
      beforeRemove: { _ in
        removalAttempts { $0 += 1 }
        throw TestError.simulatedFailure
      }
    )
    Container.shared.transcriptionQueueStore.register { store }
    Container.shared.transcriptionQueue.reset(.scope)
    Container.shared.transcriptionProcessor.reset(.scope)
    let queue = Container.shared.transcriptionQueue()
    let processor = Container.shared.transcriptionProcessor()
    let scheduler = try #require(Container.shared.bgTaskScheduler() as? FakeBGTaskScheduler)
    await queue.waitUntilLoaded()

    processor.register()
    let identifier = "\(AppInfo.bundleIdentifier).transcription"
    let task = try #require(scheduler.launchTask(withIdentifier: identifier))
    defer { task.expire() }

    try await Wait.until(
      { removalAttempts() == 1 },
      { "Background transcription did not attempt durable queue removal" }
    )
    try await Wait.until(
      maxAttempts: 100,
      { task.completionResults == [true] },
      { "Background grant remained active after retaining queued work" }
    )

    #expect(removalAttempts() == 1)
    #expect(queue.episodeIDs == [episode.id])
    #expect(!queue.failed.contains(episode.id))
    #expect(scheduler.pendingIdentifiers.contains(identifier))
    #expect(
      try await repo.episode(episode.id)?.hasTranscript
        == (scenario == .completedTranscription)
    )
  }

  @Test("a foreground drain cancels its pending background request")
  func foregroundDrainCancelsPendingRequest() async throws {
    TranscriptionHelpers.stubSpeech(
      phrases: [FakeSpeechTranscriptionResult(phrase: "hi", startSeconds: 0, endSeconds: 60)]
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

    try await queue.enqueue(episode.id)
    processor.register()
    #expect(scheduler.pendingIdentifiers.contains(identifier))

    processor.handleScenePhaseChange(to: .active)
    defer { processor.handleScenePhaseChange(to: .background) }

    try await Wait.until(
      {
        queue.episodeIDs.isEmpty
          && !scheduler.pendingIdentifiers.contains(identifier)
      },
      {
        """
        foreground task did not drain the queue and cancel its request:
          queue: \(queue.episodeIDs)
          pending: \(scheduler.pendingIdentifiers)
        """
      }
    )
  }

  @Test("foreground and background consumers never analyze the same head concurrently")
  func foregroundAndBackgroundDoNotOverlap() async throws {
    TranscriptionHelpers.stubSpeech(
      phrases: [FakeSpeechTranscriptionResult(phrase: "hi", startSeconds: 0, endSeconds: 60)]
    )
    let analyzerStarted = AsyncSemaphore(value: 0)
    let analyzerRelease = AsyncSemaphore(value: 0)
    let activeAnalyzers = ThreadSafe(0)
    let maximumActiveAnalyzers = ThreadSafe(0)
    Container.shared.speechAnalyzer.register {
      { _ in
        FakeSpeechAnalyzer { _, endTime in
          let active = activeAnalyzers {
            $0 += 1
            return $0
          }
          maximumActiveAnalyzers { $0 = max($0, active) }
          analyzerStarted.signal()
          defer { activeAnalyzers { $0 -= 1 } }
          try await analyzerRelease.waitUnlessCancelled()
          return CMTime(seconds: endTime, preferredTimescale: 600)
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

    try await queue.enqueue(episode.id)
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
        FakeSpeechAnalyzer { _, endTime in
          analyzeCount { $0 += 1 }
          analyzerStarted.signal()
          try await analyzerRelease.waitUnlessCancelled()
          return CMTime(seconds: endTime, preferredTimescale: 600)
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
    try await queue.enqueue(episode.id)

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
      phrases: [FakeSpeechTranscriptionResult(phrase: "done", startSeconds: 0, endSeconds: 60)]
    )
    let firstAnalyzerStarted = AsyncSemaphore(value: 0)
    let firstAnalyzerRelease = AsyncSemaphore(value: 0)
    let analyzeCount = ThreadSafe(0)
    Container.shared.speechAnalyzer.register {
      { _ in
        FakeSpeechAnalyzer { _, endTime in
          let count = analyzeCount {
            $0 += 1
            return $0
          }
          guard count == 1 else {
            return CMTime(seconds: endTime, preferredTimescale: 600)
          }
          firstAnalyzerStarted.signal()
          try await firstAnalyzerRelease.waitUnlessCancelled()
          return CMTime(seconds: endTime, preferredTimescale: 600)
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
    try await queue.enqueue(firstEpisode.id)
    try await queue.enqueue(secondEpisode.id)

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

  @Test("pausing the foreground head hands remaining work to a background grant")
  func pauseHandsRemainingWorkToBackground() async throws {
    TranscriptionHelpers.stubSpeech(
      phrases: [FakeSpeechTranscriptionResult(phrase: "done", startSeconds: 0, endSeconds: 60)]
    )
    let firstAnalysisStarted = AsyncSemaphore(value: 0)
    let firstAnalysisRelease = AsyncSemaphore(value: 0)
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
          if invocation == 1 {
            firstAnalysisStarted.signal()
            try await firstAnalysisRelease.waitUnlessCancelled()
          } else if invocation == 2 {
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
    let scheduler = try #require(Container.shared.bgTaskScheduler() as? FakeBGTaskScheduler)
    let firstEpisode = try await CacheHelpers.createCachedEpisode(
      title: "Cancelled foreground",
      cachedFilename: "cancelled-foreground.mp3",
      dataSize: 1
    )
    let secondEpisode = try await CacheHelpers.createCachedEpisode(
      title: "Background continuation",
      cachedFilename: "background-continuation.mp3",
      dataSize: 1
    )
    try await queue.enqueue(firstEpisode.id)
    try await queue.enqueue(secondEpisode.id)
    processor.register()
    processor.handleScenePhaseChange(to: .active)
    defer {
      firstAnalysisRelease.signal()
      secondAnalysisRelease.signal()
      processor.handleScenePhaseChange(to: .background)
    }

    await firstAnalysisStarted.wait()
    processor.handleScenePhaseChange(to: .background)
    let task = try #require(
      scheduler.launchTask(withIdentifier: "\(AppInfo.bundleIdentifier).transcription")
    )

    processor.pause(firstEpisode.id)
    await secondAnalysisStarted.wait()

    #expect(queue.episodeIDs == [secondEpisode.id])
    #expect(queue.progress[firstEpisode.id] == nil)
    #expect(try await repo.episode(firstEpisode.id)?.hasTranscript == false)
    #expect(analyzeCount() == 2)

    secondAnalysisRelease.signal()
    try await Wait.until(
      { queue.episodeIDs.isEmpty },
      { "background grant did not finish remaining work: \(queue.episodeIDs)" }
    )
    try await Wait.until(
      { task.completionResults == [true] },
      { "background grant did not complete: \(task.completionResults)" }
    )
    #expect(try await repo.episode(secondEpisode.id)?.hasTranscript == true)
    #expect(analyzeCount() == 2)
  }

  @Test("expiration cancels a preserved foreground analyzer before completing")
  func expirationCancelsPreservedForegroundAnalyzer() async throws {
    try await LogCapture.withSink { sink in
      TranscriptionHelpers.stubSpeech(
        phrases: [
          FakeSpeechTranscriptionResult(phrase: "retained", startSeconds: 0, endSeconds: 60)
        ]
      )
      let analyzerStarted = AsyncSemaphore(value: 0)
      let analyzerRelease = AsyncSemaphore(value: 0)
      let cancellationStarted = ThreadSafe(false)
      let cancellationRelease = AsyncSemaphore(value: 0)
      let cancellationCount = ThreadSafe(0)
      Container.shared.speechAnalyzer.register {
        { _ in
          FakeSpeechAnalyzer(
            analyzeAudio: { _, _ in
              analyzerStarted.signal()
              await analyzerRelease.wait()
              throw FakeSpeechError.failed
            },
            cancelAudio: {
              cancellationStarted(true)
              analyzerRelease.signal()
              await cancellationRelease.wait()
              cancellationCount { $0 += 1 }
            }
          )
        }
      }

      let queue = Container.shared.transcriptionQueue()
      let processor = Container.shared.transcriptionProcessor()
      let scheduler = try #require(Container.shared.bgTaskScheduler() as? FakeBGTaskScheduler)
      let episode = try await CacheHelpers.createCachedEpisode(
        title: "Foreground expiration",
        cachedFilename: "foreground-expiration.mp3",
        dataSize: 1
      )
      let identifier = "\(AppInfo.bundleIdentifier).transcription"
      try await queue.enqueue(episode.id)

      processor.register()
      processor.handleScenePhaseChange(to: .active)
      await analyzerStarted.wait()
      #expect(queue.progress[episode.id] != nil)

      processor.handleScenePhaseChange(to: .background)
      do {
        let task = try #require(scheduler.launchTask(withIdentifier: identifier))
        try await Wait.until(
          {
            sink.captured()
              .contains {
                $0.message.contains("event=backgroundRunStarted")
              }
          },
          { "background grant did not begin" }
        )

        task.expire()
        try await Wait.until(
          maxAttempts: 50,
          delay: .milliseconds(5),
          { cancellationStarted() },
          { "expiration did not cancel the preserved foreground analyzer" }
        )

        #expect(task.completionResults.isEmpty)
        #expect(queue.episodeIDs == [episode.id])

        cancellationRelease.signal()
        try await Wait.until(
          {
            task.completionResults == [false]
              && queue.progress[episode.id] == nil
          },
          {
            """
            expired grant completed before analyzer cleanup:
              completions: \(task.completionResults)
              progress: \(queue.progress)
            """
          }
        )
        #expect(cancellationCount() == 1)
        #expect(queue.episodeIDs == [episode.id])
        let messages = sink.captured().map(\.message)
        #expect(
          messages.contains {
            $0.contains("event=episodeCancelled")
              && $0.contains("episodeID=\(episode.id)")
          }
        )
        #expect(
          messages.contains {
            $0.contains("event=backgroundRunExpired")
              && $0.contains("remainingEpisodes=1")
          }
        )
      } catch {
        analyzerRelease.signal()
        cancellationRelease.signal()
        try await Wait.until(
          maxAttempts: 100,
          delay: .milliseconds(5),
          { queue.progress[episode.id] == nil },
          { "foreground analyzer did not finish after test cleanup" }
        )
        throw error
      }
    }
  }

  @Test("expiration retains the head for the next foreground drain")
  func expirationRetainsHeadForForeground() async throws {
    TranscriptionHelpers.stubSpeech(
      phrases: [
        FakeSpeechTranscriptionResult(phrase: "resumed", startSeconds: 0, endSeconds: 60)
      ]
    )
    let analyzerStarted = AsyncSemaphore(value: 0)
    let neverSignals = AsyncSemaphore(value: 0)
    let analyzeCount = ThreadSafe(0)
    Container.shared.speechAnalyzer.register {
      { _ in
        FakeSpeechAnalyzer { _, endTime in
          let count = analyzeCount {
            $0 += 1
            return $0
          }
          guard count == 1 else {
            return CMTime(seconds: endTime, preferredTimescale: 600)
          }
          analyzerStarted.signal()
          try await neverSignals.waitUnlessCancelled()
          return CMTime(seconds: endTime, preferredTimescale: 600)
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
    try await queue.enqueue(episode.id)

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

  @Test("expiration resumes the next background grant after durable progress")
  func expirationResumesNextBackgroundGrantAfterDurableProgress() async throws {
    let durationSeconds = 240.0
    Container.shared.fakeAudioFileProvider().setDuration(durationSeconds)
    let transcriberCount = ThreadSafe(0)
    Container.shared.speechTranscriber.register {
      { _ in
        let invocation = transcriberCount {
          $0 += 1
          return $0
        }
        let results =
          if invocation == 1 {
            [
              FakeSpeechTranscriptionResult(
                phrase: "first",
                startSeconds: 0,
                endSeconds: 120
              )
            ]
          } else if invocation == 2 {
            [
              FakeSpeechTranscriptionResult(
                phrase: "second",
                startSeconds: 120,
                endSeconds: durationSeconds
              )
            ]
          } else {
            [
              FakeSpeechTranscriptionResult(
                phrase: "first",
                startSeconds: 110,
                endSeconds: 120
              ),
              FakeSpeechTranscriptionResult(
                phrase: "second",
                startSeconds: 120,
                endSeconds: durationSeconds
              ),
            ]
          }
        return FakeSpeechTranscriber(behavior: .succeed(results))
      }
    }
    Container.shared.speechModelManager.register { FakeSpeechModelManager() }

    let expiringAnalysisStarted = ThreadSafe(false)
    let neverSignals = AsyncSemaphore(value: 0)
    defer { neverSignals.signal() }
    Container.shared.speechAnalyzer.register {
      { _ in
        FakeSpeechAnalyzer { startTime, endTime in
          if endTime == durationSeconds {
            expiringAnalysisStarted(true)
            try await neverSignals.waitUnlessCancelled()
          }
          return CMTime(seconds: endTime, preferredTimescale: 600)
        }
      }
    }

    let repo = Container.shared.repo()
    let queue = Container.shared.transcriptionQueue()
    let processor = Container.shared.transcriptionProcessor()
    let scheduler = try #require(Container.shared.bgTaskScheduler() as? FakeBGTaskScheduler)
    let episode = try await CacheHelpers.createCachedEpisode(
      title: "Durable background progress",
      cachedFilename: "durable-progress.mp3",
      dataSize: 1
    )
    let identifier = "\(AppInfo.bundleIdentifier).transcription"
    try await queue.enqueue(episode.id)
    processor.register()

    let firstTask = try #require(scheduler.launchTask(withIdentifier: identifier))
    try await Wait.until(
      { expiringAnalysisStarted() },
      { "first background grant did not begin analysis" }
    )
    firstTask.expire()
    try await Wait.until(
      { firstTask.completionResults == [false] },
      { "first background grant did not expire: \(firstTask.completionResults)" }
    )
    let persistedCheckpoint = try #require(
      try await repo.transcriptionCheckpoint(episode.id)
    )
    #expect(persistedCheckpoint.audioTime == 120)
    #expect(persistedCheckpoint.segments.map(\.text) == ["first"])

    let resumedRange = ThreadSafe<(start: TimeInterval, end: TimeInterval)?>(nil)
    let resumedAnalysisStarted = ThreadSafe(false)
    let resumedAnalysisRelease = AsyncSemaphore(value: 0)
    defer { resumedAnalysisRelease.signal() }
    Container.shared.speechAnalyzer.register {
      { _ in
        FakeSpeechAnalyzer { startTime, endTime in
          resumedRange((start: startTime, end: endTime))
          resumedAnalysisStarted(true)
          try await resumedAnalysisRelease.waitUnlessCancelled()
          return CMTime(seconds: endTime, preferredTimescale: 600)
        }
      }
    }

    let secondTask = try #require(scheduler.launchTask(withIdentifier: identifier))
    try await Wait.until(
      { resumedAnalysisStarted() },
      { "second background grant did not begin analysis" }
    )

    let capturedRange = resumedRange()
    resumedAnalysisRelease.signal()

    let range = try #require(capturedRange)
    #expect(range.start == 0)
    #expect(range.end == durationSeconds)

    try await Wait.until(
      { queue.episodeIDs.isEmpty },
      { "second background grant did not finish: \(queue.episodeIDs)" }
    )
    try await Wait.until(
      { secondTask.completionResults == [true] },
      { "second background grant did not complete: \(secondTask.completionResults)" }
    )

    let transcript = try #require(try await repo.episode(episode.id)?.decodedTranscript)
    #expect(transcript.segments.map(\.text) == ["first", "second"])
    #expect(try await repo.transcriptionCheckpoint(episode.id) == nil)
  }
}
