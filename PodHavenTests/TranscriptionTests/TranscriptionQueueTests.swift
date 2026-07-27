// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of TranscriptionQueue", .container)
struct TranscriptionQueueTests {
  private let queue = Container.shared.transcriptionQueue()

  private func makeEpisodes(_ count: Int) async throws -> [Episode] {
    Array(
      try await Container.shared.repo()
        .insertSeries(
          UnsavedPodcastSeries(
            unsavedPodcast: try Create.unsavedPodcast(),
            unsavedEpisodes: try (0..<count)
              .map {
                try Create.unsavedEpisode(guid: GUID("transcription-queue-\($0)"))
              }
          )
        )
        .episodes
    )
  }

  @Test("enqueue appends in order and ignores duplicates")
  func enqueueOrderAndDedup() async throws {
    let episodes = try await makeEpisodes(2)

    try await queue.enqueue(episodes[0].id)
    try await queue.enqueue(episodes[1].id)
    try await queue.enqueue(episodes[0].id)

    #expect(queue.episodeIDs == episodes.map(\.id))
  }

  @Test("the default capacity rejects episode 51 without changing the queue")
  func defaultCapacityBoundsQueueGrowth() async throws {
    let episodes = try await makeEpisodes(51)
    let acceptedEpisodeIDs = episodes.prefix(50).map(\.id)
    try await queue.enqueue(acceptedEpisodeIDs)

    do {
      try await queue.enqueue(episodes[50].id)
      Issue.record("Expected the full transcription queue to reject another episode")
    } catch let error as TranscriptionQueueError {
      #expect(
        error
          == .capacityExceeded(
            limit: 50,
            currentCount: 50,
            requestedCount: 1
          )
      )
      #expect(error.alertTitle == "Transcription Queue Full")
      #expect(ErrorKit.message(for: error).contains("50"))
    }

    #expect(queue.episodeIDs == acceptedEpisodeIDs)
  }

  @Test("configured capacity is clamped to the supported range")
  func capacitySettingIsClamped() {
    let settings = Container.shared.userSettings()

    settings.$maxTranscriptionQueueLength.new(1_000)
    #expect(settings.boundedMaxTranscriptionQueueLength == 100)

    settings.$maxTranscriptionQueueLength.new(-1)
    #expect(settings.boundedMaxTranscriptionQueueLength == 10)
  }

  @Test("a batch that does not fit is rejected atomically")
  func nearCapacityBatchIsAtomic() async throws {
    Container.shared.userSettings().$maxTranscriptionQueueLength.new(10)
    let episodes = try await makeEpisodes(11)
    let acceptedEpisodeIDs = episodes.prefix(9).map(\.id)
    try await queue.enqueue(acceptedEpisodeIDs)

    do {
      try await queue.enqueue(episodes.suffix(2).map(\.id))
      Issue.record("Expected the oversized batch to be rejected")
    } catch let error as TranscriptionQueueError {
      #expect(
        error
          == .capacityExceeded(
            limit: 10,
            currentCount: 9,
            requestedCount: 2
          )
      )
    }

    #expect(queue.episodeIDs == acceptedEpisodeIDs)
  }

  @Test("lowering the limit preserves existing work and blocks additions until drained")
  func loweringLimitPreservesBacklog() async throws {
    let episodes = try await makeEpisodes(12)
    Container.shared.userSettings().$maxTranscriptionQueueLength.new(100)
    try await queue.enqueue(episodes.prefix(11).map(\.id))

    Container.shared.userSettings().$maxTranscriptionQueueLength.new(10)
    await #expect(throws: TranscriptionQueueError.self) {
      try await queue.enqueue(episodes[11].id)
    }
    #expect(queue.episodeIDs == episodes.prefix(11).map(\.id))

    try await queue.remove(episodes[0].id)
    try await queue.remove(episodes[1].id)
    try await queue.enqueue(episodes[11].id)

    #expect(queue.episodeIDs == episodes.dropFirst(2).map(\.id))
  }

  @Test("reorder persists a permutation and rejects mismatched membership")
  func reorderPersistsPermutation() async throws {
    let episodes = try await makeEpisodes(3)
    let reorderedEpisodeIDs = [episodes[2].id, episodes[0].id, episodes[1].id]
    try await queue.enqueue(episodes.map(\.id))

    #expect(try await queue.reorder(reorderedEpisodeIDs))
    #expect(queue.episodeIDs == reorderedEpisodeIDs)
    let accepted = try await queue.reorder([episodes[0].id, episodes[1].id])
    #expect(!accepted)
    #expect(queue.episodeIDs == reorderedEpisodeIDs)

    Container.shared.transcriptionQueue.reset(.scope)
    let recreatedQueue = Container.shared.transcriptionQueue()
    await recreatedQueue.waitUntilLoaded()
    #expect(recreatedQueue.episodeIDs == reorderedEpisodeIDs)
  }

  @Test("persisted work survives factory recreation in order")
  func persistedWorkSurvivesFactoryRecreation() async throws {
    let episodes = try await makeEpisodes(2)
    try await queue.enqueue(episodes.map(\.id))

    Container.shared.transcriptionQueue.reset(.scope)
    let recreatedQueue = Container.shared.transcriptionQueue()
    await recreatedQueue.waitUntilLoaded()

    #expect(recreatedQueue.episodeIDs == episodes.map(\.id))
  }

  @Test("normal queue operation never reads or writes the legacy defaults key")
  func normalOperationIgnoresLegacyDefaults() async throws {
    let legacyData = Data("leave-me-alone".utf8)
    let defaults = Container.shared.standardDefaults()
    defaults.set(legacyData, forKey: "transcriptionQueue")
    let episode = try #require(try await makeEpisodes(1).first)

    try await queue.enqueue(episode.id)
    try await queue.remove(episode.id)

    #expect(defaults.data(forKey: "transcriptionQueue") == legacyData)
  }

  @Test("removing from a large imported backlog does not refetch it")
  func largeBacklogRemovalDoesNotRefetch() async throws {
    let episodeIDs = (1...10_000)
      .map {
        Episode.ID(rawValue: Int64($0))
      }
    let removedEpisodeID = episodeIDs[4_999]
    let store = FakeTranscriptionQueueStore(episodeIDs: episodeIDs)
    Container.shared.transcriptionQueueStore.register { store }
    Container.shared.transcriptionQueue.reset(.scope)
    let largeQueue = Container.shared.transcriptionQueue()
    await largeQueue.waitUntilLoaded()

    try await largeQueue.remove(removedEpisodeID)

    #expect(store.fetchCount == 1)
    #expect(store.removeCalls == [removedEpisodeID])
    #expect(largeQueue.episodeIDs.count == 9_999)
    #expect(!largeQueue.episodeIDs.contains(removedEpisodeID))
    #expect(largeQueue.episodeIDs.first == episodeIDs.first)
    #expect(largeQueue.episodeIDs.last == episodeIDs.last)
  }

  @Test("deleting an episode cascades its durable queue row")
  func episodeDeletionCascadesQueueRow() async throws {
    let episodes = try await makeEpisodes(1)
    let episode = try #require(episodes.first)
    try await queue.enqueue(episode.id)

    try await Container.shared.appDB().unsafeTestDB
      .write { db in
        try db.execute(
          sql: "DELETE FROM episode WHERE id = ?",
          arguments: [episode.id]
        )
      }

    Container.shared.transcriptionQueue.reset(.scope)
    let recreatedQueue = Container.shared.transcriptionQueue()
    await recreatedQueue.waitUntilLoaded()
    #expect(recreatedQueue.episodeIDs.isEmpty)
  }

  @Test("remove drops the episode and clears its progress")
  func removeDropsEpisode() async throws {
    let episodes = try await makeEpisodes(2)
    try await queue.enqueue(episodes.map(\.id))
    queue.setProgress(0.5, for: episodes[0].id)

    try await queue.remove(episodes[0].id)

    #expect(queue.episodeIDs == [episodes[1].id])
    #expect(queue.progress[episodes[0].id] == nil)
  }

  @Test("pausing waiting work removes it and updates remaining positions")
  func pauseWaitingWork() async throws {
    let episodes = try await makeEpisodes(3)
    try await queue.enqueue(episodes.map(\.id))

    Container.shared.transcriptionProcessor().pause(episodes[1].id)

    try await Wait.until(
      { self.queue.episodeIDs == [episodes[0].id, episodes[2].id] },
      { "Waiting transcription was not removed: \(self.queue.episodeIDs)" }
    )
    #expect(
      queue.status(for: episodes[2].id, hasTranscript: false)
        == .queued(position: 2, total: 2)
    )
    #expect(queue.interruptions[episodes[1].id] == nil)
  }

  @Test("stream yields one queue head at a time")
  func streamYieldsOneHeadAtATime() async throws {
    let episodes = try await makeEpisodes(2)

    try await queue.withWorkStream { stream in
      var iterator = stream.makeAsyncIterator()
      try await queue.enqueue(episodes.map(\.id))
      #expect(await iterator.next() == episodes[0].id)

      try await queue.remove(episodes[0].id)
      #expect(await iterator.next() == episodes[1].id)
    }
  }

  @Test("reordering the head advances the active work stream")
  func reorderAdvancesWorkStream() async throws {
    let episodes = try await makeEpisodes(3)
    try await queue.enqueue(episodes.map(\.id))

    try await queue.withWorkStream { stream in
      var iterator = stream.makeAsyncIterator()
      #expect(await iterator.next() == episodes[0].id)

      let reordered = try await queue.reorder([
        episodes[1].id, episodes[0].id, episodes[2].id,
      ])
      #expect(reordered)
      #expect(await iterator.next() == episodes[1].id)
    }
  }

  @Test("a new stream replays an interrupted head")
  func newStreamReplaysInterruptedHead() async throws {
    let episodes = try await makeEpisodes(1)
    let episode = try #require(episodes.first)
    try await queue.enqueue(episode.id)

    try await queue.withWorkStream { stream in
      var iterator = stream.makeAsyncIterator()
      #expect(await iterator.next() == episode.id)
    }
    try await queue.withWorkStream { stream in
      var iterator = stream.makeAsyncIterator()
      #expect(await iterator.next() == episode.id)
    }
  }

  @Test("status prefers transcribed and reports live queue position")
  func statusDerivation() async throws {
    let episodes = try await makeEpisodes(4)
    #expect(queue.status(for: episodes[3].id, hasTranscript: false) == .none)

    try await queue.enqueue(episodes.prefix(2).map(\.id))
    #expect(queue.status(for: episodes[0].id, hasTranscript: true) == .transcribed)
    #expect(
      queue.status(for: episodes[0].id, hasTranscript: false)
        == .queued(position: 1, total: 2)
    )
    #expect(
      queue.status(for: episodes[1].id, hasTranscript: false)
        == .queued(position: 2, total: 2)
    )

    queue.setProgress(0.25, for: episodes[0].id)
    #expect(
      queue.status(for: episodes[0].id, hasTranscript: false)
        == .transcribing(0.25)
    )
    #expect(queue.status(for: episodes[0].id, hasTranscript: false).canPause)

    #expect(try await queue.beginPausing(episodes[0].id))
    #expect(queue.status(for: episodes[0].id, hasTranscript: false) == .pausing)
    #expect(!queue.status(for: episodes[0].id, hasTranscript: false).canPause)

    queue.finishPausing(episodes[0].id)
    #expect(
      queue.status(for: episodes[1].id, hasTranscript: false)
        == .queued(position: 1, total: 1)
    )

    try await queue.fail(episodes[2].id)
    #expect(queue.status(for: episodes[2].id, hasTranscript: false) == .failed)
    #expect(
      queue.status(
        for: episodes[3].id,
        hasTranscript: false,
        checkpointProgress: 0.4
      ) == .paused(0.4)
    )
  }

  @Test("enqueue clears a prior failure for the same episode")
  func enqueueClearsFailure() async throws {
    let episodes = try await makeEpisodes(1)
    let episode = try #require(episodes.first)
    try await queue.fail(episode.id)
    #expect(queue.failed.contains(episode.id))

    try await queue.enqueue(episode.id)

    #expect(!queue.failed.contains(episode.id))
    #expect(queue.episodeIDs == [episode.id])
  }

  @Test("finishing discard clears a prior failure for the same episode")
  func finishDiscardingClearsFailure() async throws {
    let episodes = try await makeEpisodes(1)
    let episode = try #require(episodes.first)
    try await queue.fail(episode.id)
    #expect(try await queue.beginDiscarding(episode.id))

    queue.finishDiscarding(episode.id)

    #expect(!queue.failed.contains(episode.id))
    #expect(queue.status(for: episode.id, hasTranscript: false) == .none)
  }
}
