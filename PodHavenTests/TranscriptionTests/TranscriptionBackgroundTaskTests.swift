// Copyright Justin Bishop, 2026

import FactoryKit
import Testing

@testable import PodHaven

@Suite("of TranscriptionProcessor background task", .container)
struct TranscriptionBackgroundTaskTests {
  @Test("the iOS-granted background task drains the queue and completes")
  func backgroundTaskDrainsQueue() async throws {
    TranscriptionHelpers.stubSpeech(
      phrases: [FakeSpeechTranscriptionResult(phrase: "hi", startSeconds: 0)]
    )
    let repo = Container.shared.repo()
    let queue = Container.shared.transcriptionQueue()
    let processor = Container.shared.transcriptionProcessor()
    let scheduler = try #require(Container.shared.bgTaskScheduler() as? FakeBGTaskScheduler)

    let episode = try await Create.podcastEpisode(Create.unsavedEpisode(cachedFilename: "ep.mp3"))
    queue.enqueue(episode.id)

    processor.register()
    let task = try #require(
      scheduler.launchTask(withIdentifier: "\(AppInfo.bundleIdentifier).transcription")
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
  }
}
