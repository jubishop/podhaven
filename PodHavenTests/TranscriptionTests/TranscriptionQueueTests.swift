// Copyright Justin Bishop, 2026

import FactoryKit
import Testing

@testable import PodHaven

@Suite("of TranscriptionQueue", .container)
struct TranscriptionQueueTests {
  private let queue = Container.shared.transcriptionQueue()

  private func episodeIDs(_ count: Int) async throws -> [Episode.ID] {
    let series = try await Container.shared.repo()
      .insertSeries(
        UnsavedPodcastSeries(
          unsavedPodcast: try Create.unsavedPodcast(),
          unsavedEpisodes: try (0..<count)
            .map { _ in
              try Create.unsavedEpisode()
            }
        )
      )
    return series.episodes.map(\.id)
  }

  @Test("enqueue appends in order and ignores duplicates")
  func enqueueOrderAndDedup() async throws {
    let episodeIDs = try await episodeIDs(2)
    try await queue.enqueue(episodeIDs[0])
    try await queue.enqueue(episodeIDs[1])
    try await queue.enqueue(episodeIDs[0])
    #expect(queue.episodeIDs == episodeIDs)
  }

  @Test("persisted work survives factory recreation in order")
  func persistedWorkSurvivesFactoryRecreation() async throws {
    let episodeIDs = try await episodeIDs(2)
    try await queue.enqueue(episodeIDs)

    Container.shared.transcriptionQueue.reset(.scope)

    let recreatedQueue = Container.shared.transcriptionQueue()
    await recreatedQueue.waitUntilLoaded()
    #expect(recreatedQueue.episodeIDs == episodeIDs)
  }

  @Test("queue persistence does not use UserDefaults")
  func persistenceDoesNotUseUserDefaults() async throws {
    try await queue.enqueue(try await episodeIDs(1))

    #expect(
      Container.shared.standardDefaults().data(forKey: "transcriptionQueue") == nil
    )
  }

  @Test("remove drops the episode and clears its progress")
  func removeDropsEpisode() async throws {
    let episodeIDs = try await episodeIDs(2)
    try await queue.enqueue(episodeIDs)
    queue.setProgress(0.5, for: episodeIDs[0])
    try await queue.remove(episodeIDs[0])
    #expect(queue.episodeIDs == [episodeIDs[1]])
    #expect(queue.progress[episodeIDs[0]] == nil)
  }

  @Test("cancelling waiting work removes it and persists the new positions")
  func cancelWaitingWork() async throws {
    let processor = Container.shared.transcriptionProcessor()
    let episodeIDs = try await episodeIDs(3)
    try await queue.enqueue(episodeIDs)

    try await processor.cancel(episodeIDs[1])

    #expect(queue.episodeIDs == [episodeIDs[0], episodeIDs[2]])
    #expect(
      queue.status(for: episodeIDs[2], hasTranscript: false) == .queued(position: 2, total: 2)
    )

    Container.shared.transcriptionQueue.reset(.scope)
    let recreatedQueue = Container.shared.transcriptionQueue()
    await recreatedQueue.waitUntilLoaded()
    #expect(
      recreatedQueue.episodeIDs == [episodeIDs[0], episodeIDs[2]]
    )
  }

  @Test("stream yields one queue head at a time")
  func streamYieldsOneHeadAtATime() async throws {
    let episodeIDs = try await episodeIDs(2)
    try await queue.withWorkStream { stream in
      var iterator = stream.makeAsyncIterator()
      try await queue.enqueue(episodeIDs)

      #expect(await iterator.next() == episodeIDs[0])

      try await queue.remove(episodeIDs[0])
      #expect(await iterator.next() == episodeIDs[1])
    }
  }

  @Test("a new stream replays an interrupted head")
  func newStreamReplaysInterruptedHead() async throws {
    let episodeID = try await episodeIDs(1)[0]
    try await queue.enqueue(episodeID)
    try await queue.withWorkStream { stream in
      var iterator = stream.makeAsyncIterator()
      #expect(await iterator.next() == episodeID)
    }

    try await queue.withWorkStream { stream in
      var iterator = stream.makeAsyncIterator()
      #expect(await iterator.next() == episodeID)
    }
  }

  @Test("status prefers transcribed and reports live queue position")
  func statusDerivation() async throws {
    let episodeIDs = try await episodeIDs(3)
    #expect(queue.status(for: episodeIDs[2], hasTranscript: false) == .none)

    try await queue.enqueue(Array(episodeIDs.prefix(2)))
    #expect(queue.status(for: episodeIDs[0], hasTranscript: true) == .transcribed)
    #expect(
      queue.status(for: episodeIDs[0], hasTranscript: false) == .queued(position: 1, total: 2)
    )
    #expect(
      queue.status(for: episodeIDs[1], hasTranscript: false) == .queued(position: 2, total: 2)
    )

    queue.setProgress(0.25, for: episodeIDs[0])
    #expect(queue.status(for: episodeIDs[0], hasTranscript: false) == .transcribing(0.25))
    #expect(queue.status(for: episodeIDs[0], hasTranscript: false).canCancel)

    #expect(try await queue.beginCancellation(of: episodeIDs[0]))
    #expect(queue.status(for: episodeIDs[0], hasTranscript: false) == .cancelling)
    #expect(!queue.status(for: episodeIDs[0], hasTranscript: false).canCancel)

    try await queue.remove(episodeIDs[0])
    #expect(
      queue.status(for: episodeIDs[1], hasTranscript: false) == .queued(position: 1, total: 1)
    )

    try await queue.fail(episodeIDs[2])
    #expect(queue.status(for: episodeIDs[2], hasTranscript: false) == .failed)
  }

  @Test("enqueue clears a prior failure for the same episode")
  func enqueueClearsFailure() async throws {
    let episodeID = try await episodeIDs(1)[0]
    try await queue.fail(episodeID)
    #expect(queue.failed.contains(episodeID))

    try await queue.enqueue(episodeID)
    #expect(!queue.failed.contains(episodeID))
    #expect(queue.episodeIDs == [episodeID])
  }
}
