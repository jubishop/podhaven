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
      try await queue.enqueue(episodeID)
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

  @Test("media services reset rebuilds active transcription from its checkpoint")
  func mediaServicesResetRebuildsActiveTranscription() async throws {
    let durationSeconds = 121.0
    let completedAudioTime = 120.0
    TranscriptionHelpers.stubSpeech(durationSeconds: durationSeconds)
    let outputFormat = try #require(
      AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)
    )
    let transcriberCreations = ThreadSafe(0)
    Container.shared.speechTranscriber.register {
      { _ in
        transcriberCreations { $0 += 1 }
        return FakeSpeechTranscriber(
          behavior: .succeed([
            FakeSpeechTranscriptionResult(
              phrase: "resumed",
              startSeconds: completedAudioTime,
              endSeconds: durationSeconds
            )
          ])
        )
      }
    }
    let firstConvertedInputConsumed = AsyncSemaphore(value: 0)
    let firstAnalyzerRelease = AsyncSemaphore(value: 0)
    let analyzerCancellations = ThreadSafe(0)
    let analyzerCreations = ThreadSafe(0)
    let inputSequenceStartTimes = ThreadSafe<[TimeInterval]>([])
    Container.shared.speechAnalyzer.register {
      { _ in
        let invocation = analyzerCreations {
          $0 += 1
          return $0
        }
        let consumedFirstInput = ThreadSafe(false)
        return FakeSpeechAnalyzer(
          analyzeAudio: { _, _ in
            CMTime(seconds: durationSeconds, preferredTimescale: 600)
          },
          cancelAudio: {
            guard invocation == 1 else { return }
            analyzerCancellations { $0 += 1 }
            firstAnalyzerRelease.signal()
          },
          outputFormat: outputFormat,
          consumeInput: { input in
            let isFirstInput = consumedFirstInput { consumed in
              guard !consumed else { return false }
              consumed = true
              return true
            }
            guard isFirstInput else { return }
            if let startTime = input.bufferStartTime?.seconds {
              inputSequenceStartTimes { $0.append(startTime) }
            }
            guard invocation == 1 else { return }
            firstConvertedInputConsumed.signal()
            await firstAnalyzerRelease.wait()
          }
        )
      }
    }

    let repo = Container.shared.repo()
    let queue = Container.shared.transcriptionQueue()
    let processor = Container.shared.transcriptionProcessor()
    let notifier = Container.shared.notifier()
    let episode = try await CacheHelpers.createCachedEpisode(
      title: "Reset while transcribing",
      cachedFilename: "media-reset.mp3",
      dataSize: 1
    )
    let checkpoint = TranscriptionCheckpoint(
      segments: [
        TranscriptSegment(
          start: 0,
          end: completedAudioTime - 20,
          text: "completed"
        )
      ],
      audioTime: completedAudioTime,
      duration: durationSeconds,
      locale: "en-US",
      audioSHA256: FakeAudioFileHasher.defaultSHA256
    )
    try await repo.saveTranscriptionCheckpoint(checkpoint, for: episode.id)
    try await queue.enqueue(episode.id)
    processor.register()
    processor.handleScenePhaseChange(to: .active)
    defer {
      firstAnalyzerRelease.signal()
      processor.handleScenePhaseChange(to: .background)
    }

    await firstConvertedInputConsumed.wait()
    notifier.continuation(for: AVAudioSession.mediaServicesWereResetNotification)
      .yield(Notification(name: AVAudioSession.mediaServicesWereResetNotification))

    try await Wait.until(
      { analyzerCreations() == 2 },
      { "Media reset did not rebuild the active transcription" }
    )
    try await Wait.until(
      { queue.episodeIDs.isEmpty },
      { "Recovered transcription did not finish: \(queue.episodeIDs)" }
    )

    let transcript = try #require(try await repo.episode(episode.id)?.decodedTranscript)
    #expect(transcript.segments.map(\.text) == ["completed", "resumed"])
    #expect(inputSequenceStartTimes() == [110, 110])
    #expect(transcriberCreations() == 2)
    #expect(analyzerCreations() == 2)
    #expect(analyzerCancellations() == 1)
    #expect(!queue.failed.contains(episode.id))
    #expect(try await repo.transcriptionCheckpoint(episode.id) == nil)
  }

  @Test("overlapping pauses cancel active work once and clear after cleanup")
  func overlappingPausesStopActiveEpisodeOnce() async throws {
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
    let checkpoint = TranscriptionCheckpoint(
      segments: [TranscriptSegment(start: 0, end: 20, text: "partial")],
      audioTime: 30,
      duration: 60,
      locale: "en-US",
      audioSHA256: FakeAudioFileHasher.defaultSHA256
    )
    try await repo.saveTranscriptionCheckpoint(checkpoint, for: firstEpisode.id)
    try await queue.enqueue(firstEpisode.id)
    try await queue.enqueue(secondEpisode.id)
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

    try await processor.pause(firstEpisode.id)
    try await processor.pause(firstEpisode.id)
    await cancellationStarted.wait()

    #expect(queue.status(for: firstEpisode.id, hasTranscript: false) == .pausing)
    #expect(queue.episodeIDs == [secondEpisode.id])
    #expect(analyzeCount() == 1)
    #expect(cancellationCount() == 1)
    #expect(
      try await Container.shared.transcriptionQueueStore().fetchAll()
        == [secondEpisode.id]
    )

    cancellationRelease.signal()
    await secondAnalysisStarted.wait()

    #expect(queue.episodeIDs == [secondEpisode.id])
    #expect(queue.progress[firstEpisode.id] == nil)
    #expect(queue.interruptions[firstEpisode.id] == nil)
    #expect(cancellationCount() == 1)
    #expect(analyzeCount() == 2)
    #expect(try await repo.episode(firstEpisode.id)?.hasTranscript == false)
    #expect(try await repo.transcriptionCheckpoint(firstEpisode.id) == checkpoint)

    secondAnalysisRelease.signal()
    try await Wait.until(
      { queue.episodeIDs.isEmpty },
      { "next episode did not finish after cancellation: \(queue.episodeIDs)" }
    )
    #expect(try await repo.episode(secondEpisode.id)?.hasTranscript == true)
    #expect(analyzeCount() == 2)
  }

  @Test("explicit discard stops active work and deletes its checkpoint")
  func explicitDiscardStopsActiveWorkAndDeletesCheckpoint() async throws {
    TranscriptionHelpers.stubSpeech(
      phrases: [FakeSpeechTranscriptionResult(phrase: "done", startSeconds: 0, endSeconds: 60)]
    )
    let analysisStarted = AsyncSemaphore(value: 0)
    let analysisRelease = AsyncSemaphore(value: 0)
    let cancellationStarted = AsyncSemaphore(value: 0)
    let cancellationRelease = AsyncSemaphore(value: 0)
    Container.shared.speechAnalyzer.register {
      { _ in
        FakeSpeechAnalyzer(
          analyzeAudio: { _, endTime in
            analysisStarted.signal()
            try await analysisRelease.waitUnlessCancelled()
            return CMTime(seconds: endTime, preferredTimescale: 600)
          },
          cancelAudio: {
            cancellationStarted.signal()
            await cancellationRelease.wait()
          }
        )
      }
    }

    let repo = Container.shared.repo()
    let queue = Container.shared.transcriptionQueue()
    let processor = Container.shared.transcriptionProcessor()
    let episode = try await CacheHelpers.createCachedEpisode(
      title: "Discarded",
      cachedFilename: "discarded.mp3",
      dataSize: 1
    )
    let checkpoint = TranscriptionCheckpoint(
      segments: [TranscriptSegment(start: 0, end: 20, text: "partial")],
      audioTime: 30,
      duration: 60,
      locale: "en-US",
      audioSHA256: FakeAudioFileHasher.defaultSHA256
    )
    try await repo.saveTranscriptionCheckpoint(checkpoint, for: episode.id)
    try await queue.enqueue(episode.id)
    processor.handleScenePhaseChange(to: .active)
    defer {
      analysisRelease.signal()
      cancellationRelease.signal()
      processor.handleScenePhaseChange(to: .background)
    }

    await analysisStarted.wait()
    try await Wait.until(
      { queue.progress[episode.id] != nil },
      { "Active transcription did not publish progress" }
    )

    try await processor.discardProgress(for: episode.id)

    await cancellationStarted.wait()
    #expect(queue.status(for: episode.id, hasTranscript: false) == .discarding)
    cancellationRelease.signal()
    try await Wait.until(
      { queue.interruptions[episode.id] == nil },
      { "Explicit discard did not finish" }
    )
    #expect(try await repo.transcriptionCheckpoint(episode.id) == nil)
    #expect(try await repo.episode(episode.id)?.hasTranscript == false)
    #expect(queue.episodeIDs.isEmpty)
  }

  @Test("reordering the active episode retains its checkpoint and resumes it later")
  func reorderActiveEpisodeRetainsCheckpointAndResumes() async throws {
    let durationSeconds = 60.0
    TranscriptionHelpers.stubSpeech(
      phrases: [
        FakeSpeechTranscriptionResult(phrase: "overlap", startSeconds: 20, endSeconds: 30),
        FakeSpeechTranscriptionResult(phrase: "resumed", startSeconds: 30, endSeconds: 60),
      ],
      durationSeconds: durationSeconds
    )
    let firstAnalysisStarted = AsyncSemaphore(value: 0)
    let firstAnalysisRelease = AsyncSemaphore(value: 0)
    let secondAnalysisStarted = AsyncSemaphore(value: 0)
    let secondAnalysisRelease = AsyncSemaphore(value: 0)
    let resumedFirstAnalysisStarted = AsyncSemaphore(value: 0)
    let analyzeCount = ThreadSafe(0)
    Container.shared.speechAnalyzer.register {
      { _ in
        FakeSpeechAnalyzer { _, endTime in
          let invocation = analyzeCount {
            $0 += 1
            return $0
          }
          switch invocation {
          case 1:
            firstAnalysisStarted.signal()
            try await firstAnalysisRelease.waitUnlessCancelled()
          case 2:
            secondAnalysisStarted.signal()
            try await secondAnalysisRelease.waitUnlessCancelled()
          case 3:
            resumedFirstAnalysisStarted.signal()
          default:
            break
          }
          return CMTime(seconds: endTime, preferredTimescale: 600)
        }
      }
    }

    let repo = Container.shared.repo()
    let queue = Container.shared.transcriptionQueue()
    let processor = Container.shared.transcriptionProcessor()
    let firstEpisode = try await CacheHelpers.createCachedEpisode(
      title: "Partially transcribed",
      cachedFilename: "partial.mp3",
      dataSize: 1
    )
    let secondEpisode = try await CacheHelpers.createCachedEpisode(
      title: "Next in line",
      cachedFilename: "next-in-line.mp3",
      dataSize: 1
    )
    let checkpoint = TranscriptionCheckpoint(
      segments: [TranscriptSegment(start: 0, end: 20, text: "partial")],
      audioTime: 30,
      duration: durationSeconds,
      locale: "en-US",
      audioSHA256: FakeAudioFileHasher.defaultSHA256
    )
    try await repo.saveTranscriptionCheckpoint(checkpoint, for: firstEpisode.id)
    try await queue.enqueue(firstEpisode.id)
    try await queue.enqueue(secondEpisode.id)
    processor.handleScenePhaseChange(to: .active)
    defer {
      firstAnalysisRelease.signal()
      secondAnalysisRelease.signal()
      processor.handleScenePhaseChange(to: .background)
    }

    await firstAnalysisStarted.wait()
    try await Wait.until(
      { queue.progress[firstEpisode.id] != nil },
      { "Expected active episode to publish checkpoint progress" }
    )

    #expect(try await processor.reorder([secondEpisode.id, firstEpisode.id]))
    await secondAnalysisStarted.wait()

    #expect(queue.episodeIDs == [secondEpisode.id, firstEpisode.id])
    #expect(queue.progress[firstEpisode.id] == nil)
    #expect(try await repo.transcriptionCheckpoint(firstEpisode.id) == checkpoint)

    secondAnalysisRelease.signal()
    await resumedFirstAnalysisStarted.wait()
    try await Wait.until(
      { queue.episodeIDs.isEmpty },
      { "Reordered transcription queue did not finish: \(queue.episodeIDs)" }
    )

    let transcript = try #require(try await repo.episode(firstEpisode.id)?.decodedTranscript)
    #expect(transcript.segments.map(\.text) == ["partial", "overlap", "resumed"])
    #expect(try await repo.transcriptionCheckpoint(firstEpisode.id) == nil)
    #expect(analyzeCount() == 3)
  }

  @Test("a late pause cannot affect the next active episode")
  func latePauseDoesNotAffectNextEpisode() async throws {
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
    try await queue.enqueue(firstEpisode.id)
    try await queue.enqueue(secondEpisode.id)
    processor.handleScenePhaseChange(to: .active)
    defer {
      secondAnalysisRelease.signal()
      processor.handleScenePhaseChange(to: .background)
    }

    await secondAnalysisStarted.wait()
    #expect(queue.episodeIDs == [secondEpisode.id])

    try await processor.pause(firstEpisode.id)

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

  @Test("pausing waiting work revalidates it after promotion to active")
  func pauseRevalidatesWaitingWorkAfterPromotion() async throws {
    TranscriptionHelpers.stubSpeech(
      phrases: [
        FakeSpeechTranscriptionResult(
          phrase: "done",
          startSeconds: 0,
          endSeconds: 60
        )
      ]
    )
    let firstRemovalStarted = AsyncSemaphore(value: 0)
    let firstRemovalRelease = AsyncSemaphore(value: 0)
    let secondRemovalStarted = AsyncSemaphore(value: 0)
    let secondRemovalRelease = AsyncSemaphore(value: 0)
    let secondAnalysisStarted = AsyncSemaphore(value: 0)
    let secondAnalysisRelease = AsyncSemaphore(value: 0)
    let cancellationStarted = AsyncSemaphore(value: 0)
    let cancellationRelease = AsyncSemaphore(value: 0)
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
            if invocation == 2 {
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
    let firstEpisode = try await CacheHelpers.createCachedEpisode(
      title: "Finishing",
      cachedFilename: "finishing.mp3",
      dataSize: 1
    )
    let secondEpisode = try await CacheHelpers.createCachedEpisode(
      title: "Promoting",
      cachedFilename: "promoting.mp3",
      dataSize: 1
    )
    let store = FakeTranscriptionQueueStore(
      episodeIDs: [firstEpisode.id, secondEpisode.id],
      beforeRemove: { episodeID in
        if episodeID == firstEpisode.id {
          firstRemovalStarted.signal()
          await firstRemovalRelease.wait()
        } else if episodeID == secondEpisode.id {
          secondRemovalStarted.signal()
          await secondRemovalRelease.wait()
        }
      }
    )
    Container.shared.transcriptionQueueStore.register { store }
    Container.shared.transcriptionQueue.reset(.scope)
    Container.shared.transcriptionProcessor.reset(.scope)
    let queue = Container.shared.transcriptionQueue()
    let processor = Container.shared.transcriptionProcessor()
    await queue.waitUntilLoaded()
    processor.handleScenePhaseChange(to: .active)
    defer {
      firstRemovalRelease.signal()
      secondRemovalRelease.signal()
      secondAnalysisRelease.signal()
      cancellationRelease.signal()
      processor.handleScenePhaseChange(to: .background)
    }

    await firstRemovalStarted.wait()
    let pauseTask = Task {
      try await processor.pause(secondEpisode.id)
    }
    defer { pauseTask.cancel() }
    try await Wait.until(
      { queue.interruptions[secondEpisode.id] == .pausing },
      { "Waiting episode never entered the pausing state" }
    )

    firstRemovalRelease.signal()
    await secondRemovalStarted.wait()
    await secondAnalysisStarted.wait()
    #expect(queue.episodeIDs == [secondEpisode.id])
    #expect(queue.status(for: secondEpisode.id, hasTranscript: false) == .pausing)

    secondRemovalRelease.signal()
    try await pauseTask.value
    await cancellationStarted.wait()
    #expect(queue.episodeIDs.isEmpty)
    #expect(queue.interruptions[secondEpisode.id] == .pausing)

    cancellationRelease.signal()
    try await Wait.until(
      { queue.interruptions[secondEpisode.id] == nil },
      { "Promoted episode did not finish pausing" }
    )
    #expect(cancellationCount() == 1)
    #expect(analyzeCount() == 2)
    #expect(try await repo.episode(firstEpisode.id)?.hasTranscript == true)
    #expect(try await repo.episode(secondEpisode.id)?.hasTranscript == false)
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

    try await queue.enqueue(podcastEpisode.id)
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

    try await queue.enqueue(podcastEpisode.id)
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

    try await queue.enqueue(podcastEpisode.id)
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

    try await queue.enqueue(podcastEpisode.id)
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

    try await queue.enqueue(ep.id)
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

  @Test("queue removal failure preserves completed work without retrying")
  func queueRemovalFailurePreservesCompletedWork() async throws {
    TranscriptionHelpers.stubSpeech(
      phrases: [FakeSpeechTranscriptionResult(phrase: "hello", startSeconds: 0, endSeconds: 60)]
    )
    let repo = Container.shared.repo()
    let episode = try await CacheHelpers.createCachedEpisode(
      title: "Retained",
      cachedFilename: "retained.mp3",
      dataSize: 1
    )
    let removalAttempts = ThreadSafe(0)
    let laterRemovalRelease = AsyncSemaphore(value: 0)
    let store = FakeTranscriptionQueueStore(
      episodeIDs: [episode.id],
      beforeRemove: { _ in
        let attempt = removalAttempts {
          $0 += 1
          return $0
        }
        if attempt == 1 { throw TestError.simulatedFailure }
        await laterRemovalRelease.wait()
      }
    )
    Container.shared.transcriptionQueueStore.register { store }
    Container.shared.transcriptionQueue.reset(.scope)
    Container.shared.transcriptionProcessor.reset(.scope)
    let queue = Container.shared.transcriptionQueue()
    let processor = Container.shared.transcriptionProcessor()
    await queue.waitUntilLoaded()
    processor.handleScenePhaseChange(to: .active)
    defer {
      laterRemovalRelease.signal()
      processor.handleScenePhaseChange(to: .background)
    }

    try await Wait.until(
      { removalAttempts() >= 1 },
      { "Completed transcription did not attempt durable queue removal" }
    )
    try await Wait.until(
      maxAttempts: 100,
      { queue.progress[episode.id] == nil },
      { "Queue removal failure left active progress or entered a retry loop" }
    )

    #expect(removalAttempts() == 1)
    #expect(queue.episodeIDs == [episode.id])
    #expect(!queue.failed.contains(episode.id))
    #expect(try await repo.episode(episode.id)?.hasTranscript == true)
  }

  @Test("pause racing a queue removal failure clears interruption state")
  func pauseAfterQueueRemovalFailureClearsInterruption() async throws {
    TranscriptionHelpers.stubSpeech(
      phrases: [FakeSpeechTranscriptionResult(phrase: "hello", startSeconds: 0, endSeconds: 60)]
    )
    let episode = try await CacheHelpers.createCachedEpisode(
      title: "Retained then paused",
      cachedFilename: "retained-then-paused.mp3",
      dataSize: 1
    )
    let firstRemovalStarted = AsyncSemaphore(value: 0)
    let firstRemovalRelease = AsyncSemaphore(value: 0)
    let removalAttempts = ThreadSafe(0)
    let store = FakeTranscriptionQueueStore(
      episodeIDs: [episode.id],
      beforeRemove: { _ in
        let attempt = removalAttempts {
          $0 += 1
          return $0
        }
        if attempt == 1 {
          firstRemovalStarted.signal()
          await firstRemovalRelease.wait()
          throw TestError.simulatedFailure
        }
      }
    )
    Container.shared.transcriptionQueueStore.register { store }
    Container.shared.transcriptionQueue.reset(.scope)
    Container.shared.transcriptionProcessor.reset(.scope)
    let queue = Container.shared.transcriptionQueue()
    let processor = Container.shared.transcriptionProcessor()
    await queue.waitUntilLoaded()
    processor.handleScenePhaseChange(to: .active)
    defer {
      firstRemovalRelease.signal()
      processor.handleScenePhaseChange(to: .background)
    }

    await firstRemovalStarted.wait()
    let pauseTask = Task(priority: .high) {
      try await processor.pause(episode.id)
    }
    defer { pauseTask.cancel() }
    try await Wait.until(
      { queue.interruptions[episode.id] == .pausing },
      { "Episode never entered the pausing state" }
    )

    firstRemovalRelease.signal()
    try await pauseTask.value
    try await Wait.until(
      { queue.progress[episode.id] == nil },
      { "Failed removal did not finish processor cleanup" }
    )

    #expect(removalAttempts() == 2)
    #expect(queue.episodeIDs.isEmpty)
    #expect(queue.interruptions[episode.id] == nil)
  }

  @Test("failed-state removal failure preserves work without retrying")
  func failedStateRemovalFailurePreservesWork() async throws {
    TranscriptionHelpers.stubSpeechFailure()
    let repo = Container.shared.repo()
    let episode = try await CacheHelpers.createCachedEpisode(
      title: "Retained Failure",
      cachedFilename: "retained-failure.mp3",
      dataSize: 1
    )
    let removalAttempts = ThreadSafe(0)
    let laterRemovalRelease = AsyncSemaphore(value: 0)
    let store = FakeTranscriptionQueueStore(
      episodeIDs: [episode.id],
      beforeRemove: { _ in
        let attempt = removalAttempts {
          $0 += 1
          return $0
        }
        if attempt == 1 { throw TestError.simulatedFailure }
        await laterRemovalRelease.wait()
      }
    )
    Container.shared.transcriptionQueueStore.register { store }
    Container.shared.transcriptionQueue.reset(.scope)
    Container.shared.transcriptionProcessor.reset(.scope)
    let queue = Container.shared.transcriptionQueue()
    let processor = Container.shared.transcriptionProcessor()
    await queue.waitUntilLoaded()
    processor.handleScenePhaseChange(to: .active)
    defer {
      laterRemovalRelease.signal()
      processor.handleScenePhaseChange(to: .background)
    }

    try await Wait.until(
      { removalAttempts() >= 1 },
      { "Failed transcription did not attempt durable queue removal" }
    )
    try await Wait.until(
      maxAttempts: 100,
      { queue.progress[episode.id] == nil },
      { "Failed-state removal failure left active progress or entered a retry loop" }
    )

    #expect(removalAttempts() == 1)
    #expect(queue.episodeIDs == [episode.id])
    #expect(!queue.failed.contains(episode.id))
    #expect(try await repo.episode(episode.id)?.hasTranscript == false)
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

    try await queue.enqueue(ep.id)
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
