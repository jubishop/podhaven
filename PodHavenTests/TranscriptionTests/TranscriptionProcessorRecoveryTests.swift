// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Semaphore
import Testing

@testable import PodHaven

@Suite("of TranscriptionProcessor media recovery", .container)
struct TranscriptionProcessorRecoveryTests {
  enum MediaServicesRecoveryTrigger: CaseIterable, Sendable {
    case reset
    case lostThenReset
  }

  @Test(
    "media services restart rebuilds active transcription from its checkpoint",
    .timeLimit(.minutes(5)),
    arguments: MediaServicesRecoveryTrigger.allCases
  )
  func mediaServicesRestartRebuildsActiveTranscription(
    _ trigger: MediaServicesRecoveryTrigger
  ) async throws {
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
    let firstConvertedInputRelease = AsyncSemaphore(value: 0)
    let analyzerCancellations = ThreadSafe(0)
    let analyzerCreations = ThreadSafe(0)
    let inputSequenceStartTimes = ThreadSafe<[TimeInterval]>([])
    Container.shared.speechAnalyzer.register {
      { _, _ in
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
            await firstConvertedInputRelease.wait()
            throw SpeechAnalyzerInputError.conversionFailed(nil)
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
      firstConvertedInputRelease.signal()
      processor.handleScenePhaseChange(to: .background)
    }

    await firstConvertedInputConsumed.wait()
    switch trigger {
    case .reset:
      notifier.post(AVAudioSession.mediaServicesWereResetNotification)
      firstConvertedInputRelease.signal()
    case .lostThenReset:
      notifier.post(AVAudioSession.mediaServicesWereLostNotification)
      firstConvertedInputRelease.signal()
      for await progress in queue.$progress.stream()
      where progress[episode.id] == nil {
        break
      }
      #expect(queue.episodeIDs == [episode.id])
      #expect(!queue.failed.contains(episode.id))
      #expect(analyzerCreations() == 1)
      #expect(analyzerCancellations() == 1)
      notifier.post(AVAudioSession.mediaServicesWereResetNotification)
    }

    for await episodeIDs in queue.$episodeIDs.stream()
    where episodeIDs.isEmpty {
      break
    }

    let transcript = try #require(try await repo.episode(episode.id)?.decodedTranscript)
    #expect(transcript.segments.map(\.text) == ["completed", "resumed"])
    #expect(inputSequenceStartTimes() == [110, 110])
    #expect(transcriberCreations() == 2)
    #expect(analyzerCreations() == 2)
    #expect(analyzerCancellations() == 1)
    #expect(!queue.failed.contains(episode.id))
    #expect(try await repo.transcriptionCheckpoint(episode.id) == nil)
  }

  @Test("media recovery starts the reordered head rather than a stale stream value")
  func mediaRecoveryStartsReorderedHead() async throws {
    TranscriptionHelpers.stubSpeech(
      phrases: [
        FakeSpeechTranscriptionResult(
          phrase: "done",
          startSeconds: 0,
          endSeconds: 60
        )
      ]
    )
    let firstAnalysisStarted = AsyncSemaphore(value: 0)
    let firstAnalysisRelease = AsyncSemaphore(value: 0)
    let resumedAnalysisStarted = AsyncSemaphore(value: 0)
    let resumedAnalysisRelease = AsyncSemaphore(value: 0)
    let analyzerCreations = ThreadSafe(0)
    Container.shared.speechAnalyzer.register {
      { _, _ in
        let invocation = analyzerCreations {
          $0 += 1
          return $0
        }
        return FakeSpeechAnalyzer { _, endTime in
          switch invocation {
          case 1:
            firstAnalysisStarted.signal()
            try await firstAnalysisRelease.waitUnlessCancelled()
          case 2:
            resumedAnalysisStarted.signal()
            try await resumedAnalysisRelease.waitUnlessCancelled()
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
    let notifier = Container.shared.notifier()
    let firstEpisode = try await CacheHelpers.createCachedEpisode(
      title: "Stale media-services head",
      cachedFilename: "stale-media-services-head.mp3",
      dataSize: 1
    )
    let secondEpisode = try await CacheHelpers.createCachedEpisode(
      title: "Reordered media-services head",
      cachedFilename: "reordered-media-services-head.mp3",
      dataSize: 1
    )
    try await queue.enqueue([firstEpisode.id, secondEpisode.id])
    processor.register()
    processor.handleScenePhaseChange(to: .active)
    defer {
      firstAnalysisRelease.signal()
      resumedAnalysisRelease.signal()
      processor.handleScenePhaseChange(to: .background)
    }

    await firstAnalysisStarted.wait()
    notifier.post(AVAudioSession.mediaServicesWereLostNotification)
    try await Wait.until(
      { queue.progress[firstEpisode.id] == nil },
      { "Lost media services did not release the active head" }
    )
    #expect(try await processor.reorder([secondEpisode.id, firstEpisode.id]))

    notifier.post(AVAudioSession.mediaServicesWereResetNotification)
    await resumedAnalysisStarted.wait()

    #expect(queue.progress[secondEpisode.id] != nil)
    #expect(queue.progress[firstEpisode.id] == nil)
    resumedAnalysisRelease.signal()
    try await Wait.until(
      { queue.episodeIDs.isEmpty },
      { "Reordered media-services queue did not drain: \(queue.episodeIDs)" }
    )
    #expect(try await repo.episode(firstEpisode.id)?.hasTranscript == true)
    #expect(try await repo.episode(secondEpisode.id)?.hasTranscript == true)
  }
}
