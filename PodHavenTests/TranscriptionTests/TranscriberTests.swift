// Copyright Justin Bishop, 2026

import CoreMedia
import FactoryKit
import Foundation
import Semaphore
import Testing

@testable import PodHaven

@Suite("of Transcriber", .container)
struct TranscriberTests {
  private let fileURL = URL(fileURLWithPath: "/dev/null")
  private let logContext = TranscriptionLogContext(
    runID: "transcriber-test",
    mode: .foreground,
    episodeID: Episode.ID(rawValue: -1)
  )
  private let locale = Locale(identifier: "en-US")
  private let audioSHA256 = FakeAudioFileHasher.defaultSHA256

  @Test("maps phrases to segments, trimming whitespace and dropping empties")
  func mapsPhrasesToSegments() async throws {
    TranscriptionHelpers.stubSpeech(phrases: [
      FakeSpeechTranscriptionResult(phrase: "  hello  ", startSeconds: 1.5, endSeconds: 2),
      FakeSpeechTranscriptionResult(phrase: "   ", startSeconds: 2, endSeconds: 2.5),
      FakeSpeechTranscriptionResult(phrase: "world", startSeconds: nil, endSeconds: 3),
    ])

    let segments = try await Container.shared.transcriber()
      .transcribe(
        fileURL: fileURL,
        locale: locale,
        logContext: logContext
      )

    #expect(segments.count == 2)
    #expect(segments.first?.text == "hello")
    #expect(segments.first?.start == 1.5)
    #expect(segments.last?.text == "world")
    #expect(segments.last?.start == 0)
  }

  @Test("rejects a phrase without an audio end time")
  func rejectsPhraseWithoutEndTime() async throws {
    TranscriptionHelpers.stubSpeech(phrases: [
      FakeSpeechTranscriptionResult(phrase: "untimed", startSeconds: 0, endSeconds: nil)
    ])

    await #expect(throws: TranscriptionError.self) {
      try await Container.shared.transcriber()
        .transcribe(fileURL: fileURL, locale: locale, logContext: logContext)
    }
  }

  @Test("reports monotonic progress from each result's audio end over the duration")
  func reportsProgress() async throws {
    TranscriptionHelpers.stubSpeech(
      phrases: [
        FakeSpeechTranscriptionResult(phrase: "a", startSeconds: 0, endSeconds: 25),
        FakeSpeechTranscriptionResult(phrase: "b", startSeconds: 25, endSeconds: 50),
        FakeSpeechTranscriptionResult(phrase: "c", startSeconds: 50, endSeconds: 100),
      ],
      durationSeconds: 100
    )

    let reported = ThreadSafe<[Double]>([])
    let segments = try await Container.shared.transcriber()
      .transcribe(fileURL: fileURL, locale: locale, logContext: logContext) { progress in
        reported { $0.append(progress) }
      }

    #expect(segments.count == 3)
    #expect(reported() == [0.25, 0.5, 1])
  }

  @Test("logs chunk wall time and audio throughput")
  func logsChunkTiming() async throws {
    try await LogCapture.withSink { sink in
      let durationSeconds = 120.0
      TranscriptionHelpers.stubSpeech(
        phrases: [
          FakeSpeechTranscriptionResult(
            phrase: "timed",
            startSeconds: 0,
            endSeconds: durationSeconds
          )
        ],
        durationSeconds: durationSeconds
      )
      let clock = Container.shared.fakeContinuousClock()
      clock.freeze()
      Container.shared.speechAnalyzer.register {
        { _ in
          FakeSpeechAnalyzer(durationSeconds: durationSeconds) { _, endTime in
            clock.advance(by: .seconds(30))
            return CMTime(seconds: endTime, preferredTimescale: 600)
          }
        }
      }

      _ = try await Container.shared.transcriber()
        .transcribe(
          fileURL: fileURL,
          locale: locale,
          logContext: logContext
        )

      let messages = sink.captured().map(\.message)
      #expect(
        messages.contains {
          $0.contains("event=chunkStarted")
            && $0.contains("runID=transcriber-test")
            && $0.contains("analyzedAudioSeconds=120.0")
        }
      )
      #expect(
        messages.contains {
          $0.contains("event=chunkCompleted")
            && $0.contains("wallSeconds=30.0")
            && $0.contains("audioToWallRatio=4.0")
        }
      )
    }
  }

  @Test("throws when the locale's model is unsupported")
  func throwsWhenLocaleUnsupported() async throws {
    TranscriptionHelpers.stubSpeech(
      modelManager: FakeSpeechModelManager(supportedIdentifiers: [], installedIdentifiers: [])
    )

    await #expect(throws: TranscriptionError.self) {
      try await Container.shared.transcriber()
        .transcribe(fileURL: fileURL, locale: locale, logContext: logContext)
    }
  }

  @Test("installs the model when supported but not yet installed")
  func installsWhenNotInstalled() async throws {
    let modelManager = TranscriptionHelpers.stubSpeech(
      phrases: [FakeSpeechTranscriptionResult(phrase: "hi", startSeconds: 0, endSeconds: 60)],
      modelManager: FakeSpeechModelManager(
        supportedIdentifiers: ["en-US"],
        installedIdentifiers: []
      )
    )

    let segments = try await Container.shared.transcriber()
      .transcribe(
        fileURL: fileURL,
        locale: locale,
        logContext: logContext
      )

    #expect(segments.first?.text == "hi")
    #expect(modelManager.installRequests() == ["en-US"])
  }

  @Test("propagates transcription failures")
  func propagatesFailures() async throws {
    TranscriptionHelpers.stubSpeechFailure()

    await #expect(throws: FakeSpeechError.self) {
      try await Container.shared.transcriber()
        .transcribe(fileURL: fileURL, locale: locale, logContext: logContext)
    }
  }

  @Test("resuming replaces segments that cross the overlap boundary")
  func resumeReplacesOverlappingSegments() async throws {
    let durationSeconds = 240.0
    TranscriptionHelpers.stubSpeech(
      phrases: [
        FakeSpeechTranscriptionResult(
          phrase: "replacement boundary",
          startSeconds: 100,
          endSeconds: 125
        ),
        FakeSpeechTranscriptionResult(
          phrase: "later",
          startSeconds: 125,
          endSeconds: durationSeconds
        ),
      ],
      durationSeconds: durationSeconds
    )
    let analyzedRange = ThreadSafe<(start: TimeInterval, end: TimeInterval)?>(nil)
    Container.shared.speechAnalyzer.register {
      { _ in
        FakeSpeechAnalyzer(durationSeconds: durationSeconds) { startTime, endTime in
          analyzedRange((start: startTime, end: endTime))
          return CMTime(seconds: endTime, preferredTimescale: 600)
        }
      }
    }
    let checkpoint = TranscriptionCheckpoint(
      segments: [
        TranscriptSegment(start: 0, end: 100, text: "early"),
        TranscriptSegment(start: 100, end: 120, text: "old boundary"),
      ],
      audioTime: 120,
      duration: durationSeconds,
      locale: locale.identifier(.bcp47),
      audioSHA256: audioSHA256
    )
    let savedCheckpoint = ThreadSafe<TranscriptionCheckpoint?>(nil)

    let segments = try await Container.shared.transcriber()
      .transcribe(
        fileURL: fileURL,
        locale: locale,
        logContext: logContext,
        checkpoint: checkpoint,
        onCheckpoint: { savedCheckpoint($0) }
      )

    #expect(analyzedRange()?.start == 100)
    #expect(analyzedRange()?.end == durationSeconds)
    #expect(segments.map(\.text) == ["early", "replacement boundary", "later"])
    #expect(savedCheckpoint()?.audioTime == durationSeconds)
    #expect(savedCheckpoint()?.audioSHA256 == audioSHA256)
  }

  @Test("a partial analysis does not advance the checkpoint")
  func partialAnalysisDoesNotAdvanceCheckpoint() async throws {
    let durationSeconds = 120.0
    TranscriptionHelpers.stubSpeech(durationSeconds: durationSeconds)
    Container.shared.speechAnalyzer.register {
      { _ in
        FakeSpeechAnalyzer(durationSeconds: durationSeconds) { _, _ in
          CMTime(seconds: 60, preferredTimescale: 600)
        }
      }
    }
    let savedCheckpoint = ThreadSafe<TranscriptionCheckpoint?>(nil)

    await #expect(throws: TranscriptionError.self) {
      try await Container.shared.transcriber()
        .transcribe(
          fileURL: fileURL,
          locale: locale,
          logContext: logContext,
          onCheckpoint: { savedCheckpoint($0) }
        )
    }

    #expect(savedCheckpoint() == nil)
  }

  @Test("cancellation returning partial coverage does not advance the checkpoint")
  func cancelledPartialAnalysisDoesNotAdvanceCheckpoint() async throws {
    let durationSeconds = 120.0
    TranscriptionHelpers.stubSpeech(durationSeconds: durationSeconds)
    let analyzerStarted = AsyncSemaphore(value: 0)
    let analyzerRelease = AsyncSemaphore(value: 0)
    Container.shared.speechAnalyzer.register {
      { _ in
        FakeSpeechAnalyzer(
          durationSeconds: durationSeconds,
          analyzeAudio: { _, _ in
            analyzerStarted.signal()
            await analyzerRelease.wait()
            return CMTime(seconds: 60, preferredTimescale: 600)
          },
          cancelAudio: {
            analyzerRelease.signal()
          }
        )
      }
    }
    let savedCheckpoint = ThreadSafe<TranscriptionCheckpoint?>(nil)
    let task = Task {
      try await Container.shared.transcriber()
        .transcribe(
          fileURL: fileURL,
          locale: locale,
          logContext: logContext,
          onCheckpoint: { savedCheckpoint($0) }
        )
    }
    await analyzerStarted.wait()

    task.cancel()

    await #expect(throws: CancellationError.self) {
      try await task.value
    }
    #expect(savedCheckpoint() == nil)
  }

  @Test("an incompatible checkpoint restarts from zero")
  func incompatibleCheckpointRestartsFromZero() async throws {
    let durationSeconds = 60.0
    TranscriptionHelpers.stubSpeech(
      phrases: [
        FakeSpeechTranscriptionResult(
          phrase: "fresh",
          startSeconds: 0,
          endSeconds: 30
        )
      ],
      durationSeconds: durationSeconds
    )
    let analyzedRange = ThreadSafe<(start: TimeInterval, end: TimeInterval)?>(nil)
    Container.shared.speechAnalyzer.register {
      { _ in
        FakeSpeechAnalyzer(durationSeconds: durationSeconds) { startTime, endTime in
          analyzedRange((start: startTime, end: endTime))
          return CMTime(seconds: endTime, preferredTimescale: 600)
        }
      }
    }
    let staleCheckpoint = TranscriptionCheckpoint(
      segments: [TranscriptSegment(start: 0, end: 120, text: "stale")],
      audioTime: 120,
      duration: 240,
      locale: locale.identifier(.bcp47),
      audioSHA256: audioSHA256
    )
    let reportedProgress = ThreadSafe<[Double]>([])

    let segments = try await Container.shared.transcriber()
      .transcribe(
        fileURL: fileURL,
        locale: locale,
        logContext: logContext,
        checkpoint: staleCheckpoint,
        onProgress: { progress in reportedProgress { $0.append(progress) } }
      )

    #expect(analyzedRange()?.start == 0)
    #expect(analyzedRange()?.end == durationSeconds)
    #expect(segments.map(\.text) == ["fresh"])
    #expect(reportedProgress() == [0, 0.5])
  }

  @Test("a same-duration checkpoint for different audio restarts from zero")
  func changedAudioRestartsFromZero() async throws {
    let durationSeconds = 60.0
    TranscriptionHelpers.stubSpeech(
      phrases: [
        FakeSpeechTranscriptionResult(
          phrase: "fresh",
          startSeconds: 0,
          endSeconds: durationSeconds
        )
      ],
      durationSeconds: durationSeconds
    )
    let analyzedRange = ThreadSafe<(start: TimeInterval, end: TimeInterval)?>(nil)
    Container.shared.speechAnalyzer.register {
      { _ in
        FakeSpeechAnalyzer(durationSeconds: durationSeconds) { startTime, endTime in
          analyzedRange((start: startTime, end: endTime))
          return CMTime(seconds: endTime, preferredTimescale: 600)
        }
      }
    }
    let staleCheckpoint = try TranscriptionCheckpoint(
      decoding: """
        {
          "segments": [{"start": 0, "end": 20, "text": "stale"}],
          "audioTime": 30,
          "duration": 60,
          "locale": "en-US",
          "audioSHA256": "0000000000000000000000000000000000000000000000000000000000000000"
        }
        """
    )

    let segments = try await Container.shared.transcriber()
      .transcribe(
        fileURL: fileURL,
        locale: locale,
        logContext: logContext,
        checkpoint: staleCheckpoint
      )

    #expect(analyzedRange()?.start == 0)
    #expect(analyzedRange()?.end == durationSeconds)
    #expect(segments.map(\.text) == ["fresh"])
  }

  @Test("cancelling transcription waits for the analyzer to finish")
  func cancellationWaitsForAnalyzer() async throws {
    TranscriptionHelpers.stubSpeech()
    let analyzerStarted = AsyncSemaphore(value: 0)
    let analyzerRelease = AsyncSemaphore(value: 0)
    let cancellationStarted = AsyncSemaphore(value: 0)
    let cancellationRelease = AsyncSemaphore(value: 0)
    let analyzerCancelled = ThreadSafe(0)
    let transcriptionFinished = ThreadSafe(false)
    Container.shared.speechAnalyzer.register {
      { _ in
        FakeSpeechAnalyzer(
          analyzeAudio: { _, _ in
            analyzerStarted.signal()
            await analyzerRelease.wait()
            throw FakeSpeechError.failed
          },
          cancelAudio: {
            cancellationStarted.signal()
            analyzerRelease.signal()
            await cancellationRelease.wait()
            analyzerCancelled { $0 += 1 }
          }
        )
      }
    }

    let task = Task {
      defer { transcriptionFinished(true) }
      _ = try await Container.shared.transcriber()
        .transcribe(fileURL: fileURL, locale: locale, logContext: logContext)
    }
    await analyzerStarted.wait()
    task.cancel()
    await cancellationStarted.wait()

    do {
      try await Wait.until(
        maxAttempts: 50,
        delay: .milliseconds(5),
        { transcriptionFinished() },
        { "cancelled transcription returned before analyzer cleanup finished" }
      )
    } catch {
      // The timeout is expected while analyzer cleanup is held at the gate.
    }
    #expect(!transcriptionFinished())

    cancellationRelease.signal()
    await #expect(throws: CancellationError.self) {
      try await task.value
    }
    #expect(analyzerCancelled() == 1)
  }

  @Test("throws when the audio file decodes to no audio")
  func throwsWhenNoDecodableAudio() async throws {
    TranscriptionHelpers.stubSpeech(phrases: [
      FakeSpeechTranscriptionResult(phrase: "ignored", startSeconds: 0, endSeconds: 60)
    ])
    Container.shared.speechAnalyzer.register {
      { _ in FakeSpeechAnalyzer(analyzeAudio: { _, _ in nil }) }
    }

    await #expect(throws: TranscriptionError.self) {
      try await Container.shared.transcriber()
        .transcribe(fileURL: fileURL, locale: locale, logContext: logContext)
    }
  }

  @Test("cancelling no-audio cleanup cancels the analyzer once")
  func cancellingNoAudioCleanupCancelsAnalyzerOnce() async throws {
    TranscriptionHelpers.stubSpeech()
    let cancellationStarted = AsyncSemaphore(value: 0)
    let cancellationRelease = AsyncSemaphore(value: 0)
    let cancellationCount = ThreadSafe(0)
    Container.shared.speechAnalyzer.register {
      { _ in
        FakeSpeechAnalyzer(
          analyzeAudio: { _, _ in nil },
          cancelAudio: {
            let invocation = cancellationCount { count in
              count += 1
              return count
            }
            if invocation == 1 {
              cancellationStarted.signal()
              await cancellationRelease.wait()
            }
          }
        )
      }
    }

    let task = Task {
      try await Container.shared.transcriber()
        .transcribe(fileURL: fileURL, locale: locale, logContext: logContext)
    }
    await cancellationStarted.wait()

    task.cancel()
    cancellationRelease.signal()

    await #expect(throws: CancellationError.self) {
      try await task.value
    }
    #expect(cancellationCount() == 1)
  }

  @Test("returns no segments when audio has no recognizable speech")
  func returnsNoSegmentsForSpeechlessAudio() async throws {
    TranscriptionHelpers.stubSpeech(phrases: [])

    let segments = try await Container.shared.transcriber()
      .transcribe(
        fileURL: fileURL,
        locale: locale,
        logContext: logContext
      )

    #expect(segments.isEmpty)
  }
}
