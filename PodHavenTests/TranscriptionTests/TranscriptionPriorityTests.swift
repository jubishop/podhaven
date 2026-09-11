// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Speech
import Testing

@testable import PodHaven

@Suite("of transcription processing priority", .container)
struct TranscriptionPriorityTests {
  enum EntryPoint: CaseIterable, Sendable {
    case foreground
    case background
  }

  @Test(
    "every chunk requests background engine processing through the real worker",
    .timeLimit(.minutes(5)),
    arguments: EntryPoint.allCases
  )
  func configuresEveryChunk(_ entryPoint: EntryPoint) async throws {
    TranscriptionHelpers.stubSpeech(durationSeconds: 121)
    let callingPriority = Task.currentPriority
    let requestedPriorities = ThreadSafe<[TaskPriority?]>([])
    Container.shared.taskPriority.context(.test) {
      { priority in
        requestedPriorities { $0.append(priority) }
        return nil
      }
    }
    let constructionPriorities = ThreadSafe<[TaskPriority]>([])
    let inputPriorities = ThreadSafe<[TaskPriority]>([])
    let analysisPriorities = ThreadSafe<[TaskPriority]>([])
    let configurations = ThreadSafe<[SpeechAnalyzer.Options?]>([])
    Container.shared.speechAnalyzer.register {
      { _, options in
        configurations { $0.append(options) }
        constructionPriorities { $0.append(Task.currentPriority) }
        return FakeSpeechAnalyzer(
          analyzeAudio: { _, endTime in
            analysisPriorities { $0.append(Task.currentPriority) }
            return CMTime(seconds: endTime, preferredTimescale: 600)
          },
          consumeInput: { _ in
            inputPriorities { $0.append(Task.currentPriority) }
          }
        )
      }
    }

    let queue = Container.shared.transcriptionQueue()
    let processor = Container.shared.transcriptionProcessor()
    let scheduler = try #require(Container.shared.bgTaskScheduler() as? FakeBGTaskScheduler)
    let episode = try await CacheHelpers.createCachedEpisode(
      title: "Priority propagation",
      cachedFilename: "priority.mp3",
      dataSize: 1
    )
    try await queue.enqueue(episode.id)
    processor.register()
    defer { processor.handleScenePhaseChange(to: .background) }

    let backgroundTask: FakeBGTask?
    switch entryPoint {
    case .foreground:
      backgroundTask = nil
      processor.handleScenePhaseChange(to: .active)
    case .background:
      let launchedTask = try #require(
        scheduler.launchTask(withIdentifier: "\(AppInfo.bundleIdentifier).transcription")
      )
      backgroundTask = launchedTask
    }
    for await episodeIDs in queue.$episodeIDs.stream()
    where episodeIDs.isEmpty {
      break
    }
    if let backgroundTask {
      try await Wait.until(
        { backgroundTask.completionResults == [true] },
        { "The background grant did not complete" }
      )
    }

    let capturedConfigurations = configurations()
    #expect(capturedConfigurations.count == 2)
    for options in capturedConfigurations {
      #expect(options?.priority == .background)
      #expect(options?.modelRetention == .whileInUse)
    }
    #expect(constructionPriorities().count == 2)
    #expect(analysisPriorities().count == 2)
    #expect(!inputPriorities().isEmpty)
    #expect(constructionPriorities().allSatisfy { $0 >= callingPriority })
    #expect(inputPriorities().allSatisfy { $0 >= callingPriority })
    #expect(analysisPriorities().allSatisfy { $0 >= callingPriority })
    if case .foreground = entryPoint {
      #expect(requestedPriorities().contains(.background))
    }
    let episodeAfter = try await Container.shared.repo().episode(episode.id)
    #expect(episodeAfter?.hasTranscript == true)
  }
}
