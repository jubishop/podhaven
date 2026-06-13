// Copyright Justin Bishop, 2026

import FactoryKit
import Testing

@testable import PodHaven

@Suite("of TranscriptionProcessor", .container)
struct TranscriptionProcessorTests {
  @Test("drains queued episodes one at a time, writing transcripts")
  func drainsQueueWritingTranscripts() async throws {
    Container.shared.transcriber.register {
      FakeTranscriber(behavior: .succeed([TranscriptSegment(start: 0, text: "hello")]))
    }
    let repo = Container.shared.repo()
    let queue = Container.shared.transcriptionQueue()
    let processor = Container.shared.transcriptionProcessor()

    let ep1 = try await Create.podcastEpisode(Create.unsavedEpisode(cachedFilename: "ep1.mp3"))
    let ep2 = try await Create.podcastEpisode(Create.unsavedEpisode(cachedFilename: "ep2.mp3"))

    queue.enqueue([ep1.id, ep2.id])
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

  @Test("a failing transcription is marked failed and dequeued")
  func failureMarksFailedAndDequeues() async throws {
    Container.shared.transcriber.register { FakeTranscriber(behavior: .fail) }
    let repo = Container.shared.repo()
    let queue = Container.shared.transcriptionQueue()
    let processor = Container.shared.transcriptionProcessor()

    let ep = try await Create.podcastEpisode(Create.unsavedEpisode(cachedFilename: "ep.mp3"))

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
}
