// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Semaphore
import Testing

@testable import PodHaven

@Suite("of TranscriptionQueueViewModel tests", .container)
@MainActor final class TranscriptionQueueViewModelTests {
  @DynamicInjected(\.appDB) private var appDB
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.transcriptionQueue) private var transcriptionQueue

  @Test("loads queue order with live and checkpoint progress")
  func loadsQueueOrderAndProgress() async throws {
    let episodes = try await makeEpisodes()
    let checkpoint = TranscriptionCheckpoint(
      segments: [],
      audioTime: 900,
      duration: 3600,
      locale: TranscriptionAvailability.locale.identifier(.bcp47),
      audioSHA256: String(repeating: "a", count: 64)
    )
    try await repo.saveTranscriptionCheckpoint(checkpoint, for: episodes[1].id)
    for episode in episodes {
      try await transcriptionQueue.enqueue(episode.id)
    }
    transcriptionQueue.setProgress(0.42, for: episodes[0].id)

    let viewModel = TranscriptionQueueViewModel()
    let executeTask = Task { await viewModel.execute() }
    defer { executeTask.cancel() }

    try await Wait.until(
      { @MainActor in viewModel.entries.count == 3 },
      { @MainActor in
        "Expected 3 transcription queue rows, got \(viewModel.entries.count)"
      }
    )

    #expect(viewModel.entries.map(\.id) == episodes.map(\.id))
    #expect(viewModel.entries[0].isActive)
    #expect(viewModel.entries[0].progress == 0.42)
    #expect(!viewModel.entries[1].isActive)
    #expect(viewModel.entries[1].progress == 0.25)
    #expect(viewModel.entries[2].progress == 0)
    #expect(viewModel.activeEntry?.id == episodes[0].id)
    #expect(viewModel.waitingEntries.map(\.id) == [episodes[1].id, episodes[2].id])

    viewModel.selectAll()
    #expect(viewModel.selectedEpisodeIDs == [episodes[1].id, episodes[2].id])
    #expect(viewModel.allSelected)
  }

  @Test("moving waiting work to the top preserves the active transcription")
  func movingWaitingWorkToTopPreservesActiveTranscription() async throws {
    let episodes = try await makeEpisodes()
    for episode in episodes {
      try await transcriptionQueue.enqueue(episode.id)
    }
    transcriptionQueue.setProgress(0.42, for: episodes[0].id)

    let viewModel = TranscriptionQueueViewModel()
    let executeTask = Task { await viewModel.execute() }
    defer { executeTask.cancel() }

    try await Wait.until(
      { @MainActor in viewModel.entries.map(\.id) == episodes.map(\.id) },
      { @MainActor in "Expected initial queue order" }
    )

    viewModel.moveToTop(episodes[2].id, swipeAction: false)

    let expectedOrder = [episodes[0].id, episodes[2].id, episodes[1].id]
    #expect(viewModel.entries.map(\.id) == expectedOrder)
    try await Wait.until(
      { @MainActor in
        self.transcriptionQueue.episodeIDs == viewModel.entries.map(\.id)
      },
      { @MainActor in "Expected projected queue order to persist" }
    )
  }

  @Test("swipe move hides its row until the queue reorder finishes")
  func swipeMoveHidesRowUntilQueueReorderFinishes() async throws {
    let episodes = try await makeEpisodes()
    let episodeIDs = episodes.map(\.id)
    let reorderStarted = AsyncSemaphore(value: 0)
    let reorderRelease = AsyncSemaphore(value: 0)
    let store = FakeTranscriptionQueueStore(
      episodeIDs: episodeIDs,
      beforeReorder: { _ in
        reorderStarted.signal()
        await reorderRelease.wait()
      }
    )
    Container.shared.transcriptionQueueStore.register { store }
    Container.shared.transcriptionQueue.reset(.scope)
    Container.shared.transcriptionProcessor.reset(.scope)
    let queue = Container.shared.transcriptionQueue()
    await queue.waitUntilLoaded()

    let viewModel = TranscriptionQueueViewModel()
    let executeTask = Task { await viewModel.execute() }
    defer {
      reorderRelease.signal()
      executeTask.cancel()
    }

    try await Wait.until(
      { @MainActor in viewModel.entries.map(\.id) == episodeIDs },
      { @MainActor in "Expected initial queue order" }
    )

    viewModel.moveToTop(episodes[2].id, swipeAction: true)

    let visibleWhilePending = [episodes[0].id, episodes[1].id]
    #expect(viewModel.entries.map(\.id) == visibleWhilePending)
    await reorderStarted.wait()
    #expect(viewModel.entries.map(\.id) == visibleWhilePending)

    reorderRelease.signal()
    let expectedOrder = [episodes[2].id, episodes[0].id, episodes[1].id]
    try await Wait.until(
      { @MainActor in
        queue.episodeIDs == expectedOrder && viewModel.entries.map(\.id) == expectedOrder
      },
      { @MainActor in "Expected the moved row to reappear at the persisted destination" }
    )
  }

  @Test("Transcribe Now swipe hides its row until the queue reorder finishes")
  func transcribeNowSwipeHidesRowUntilQueueReorderFinishes() async throws {
    let episodes = try await makeEpisodes()
    let episodeIDs = episodes.map(\.id)
    let reorderStarted = AsyncSemaphore(value: 0)
    let reorderRelease = AsyncSemaphore(value: 0)
    let store = FakeTranscriptionQueueStore(
      episodeIDs: episodeIDs,
      beforeReorder: { _ in
        reorderStarted.signal()
        await reorderRelease.wait()
      }
    )
    Container.shared.transcriptionQueueStore.register { store }
    Container.shared.transcriptionQueue.reset(.scope)
    Container.shared.transcriptionProcessor.reset(.scope)
    let queue = Container.shared.transcriptionQueue()
    await queue.waitUntilLoaded()
    queue.setProgress(0.42, for: episodes[0].id)

    let viewModel = TranscriptionQueueViewModel()
    let executeTask = Task { await viewModel.execute() }
    defer {
      reorderRelease.signal()
      executeTask.cancel()
    }

    try await Wait.until(
      { @MainActor in viewModel.entries.map(\.id) == episodeIDs },
      { @MainActor in "Expected initial queue order" }
    )

    viewModel.transcribeNow(episodes[2].id, swipeAction: true)

    let visibleWhilePending = [episodes[0].id, episodes[1].id]
    #expect(viewModel.entries.map(\.id) == visibleWhilePending)
    await reorderStarted.wait()
    #expect(viewModel.entries.map(\.id) == visibleWhilePending)

    reorderRelease.signal()
    let expectedOrder = [episodes[2].id, episodes[0].id, episodes[1].id]
    try await Wait.until(
      { @MainActor in
        queue.episodeIDs == expectedOrder && viewModel.entries.map(\.id) == expectedOrder
      },
      { @MainActor in
        "Expected Transcribe Now to reveal the moved row at the persisted destination"
      }
    )
  }

  @Test("transcribe now keeps the interrupted active episode floated and requeued first")
  func transcribeNowKeepsInterruptedActiveEpisodeFloated() async throws {
    let episodes = try await makeEpisodes()
    for episode in episodes {
      try await transcriptionQueue.enqueue(episode.id)
    }
    transcriptionQueue.setProgress(0.42, for: episodes[0].id)

    let viewModel = TranscriptionQueueViewModel()
    let executeTask = Task { await viewModel.execute() }
    defer { executeTask.cancel() }

    try await Wait.until(
      { @MainActor in viewModel.entries.map(\.id) == episodes.map(\.id) },
      { @MainActor in "Expected initial queue order" }
    )

    viewModel.transcribeNow(episodes[2].id, swipeAction: false)

    let firstExpectedOrder = [episodes[2].id, episodes[0].id, episodes[1].id]
    #expect(viewModel.entries.map(\.id) == firstExpectedOrder)
    #expect(viewModel.activeEntry?.id == episodes[0].id)
    #expect(viewModel.waitingEntries.map(\.id) == [episodes[2].id, episodes[1].id])
    try await Wait.until(
      { @MainActor in self.transcriptionQueue.episodeIDs == firstExpectedOrder },
      { @MainActor in "Expected Transcribe Now order to persist" }
    )

    viewModel.transcribeNow(episodes[1].id, swipeAction: false)

    let secondExpectedOrder = [episodes[1].id, episodes[0].id, episodes[2].id]
    #expect(viewModel.entries.map(\.id) == secondExpectedOrder)
    #expect(viewModel.activeEntry?.id == episodes[0].id)
    #expect(viewModel.waitingEntries.map(\.id) == [episodes[1].id, episodes[2].id])
    try await Wait.until(
      { @MainActor in self.transcriptionQueue.episodeIDs == secondExpectedOrder },
      { @MainActor in "Expected the latest promotion to keep interrupted work requeued first" }
    )
  }

  @Test("queue progress shows only its percentage while announcing status")
  func queueProgressShowsOnlyItsPercentageWhileAnnouncingStatus() async throws {
    let episode = try await Create.podcastEpisode()
    let waitingEntry = TranscriptionQueueViewModel.Entry(
      episode: episode,
      progress: 0.25,
      isActive: false
    )
    let activeEntry = TranscriptionQueueViewModel.Entry(
      episode: episode,
      progress: 0.42,
      isActive: true
    )

    #expect(waitingEntry.progressText == "25%")
    #expect(waitingEntry.accessibilityValue == "Waiting, 25 percent complete")
    #expect(activeEntry.progressText == "42%")
    #expect(activeEntry.accessibilityValue == "Transcribing, 42 percent")
  }

  @Test("an unreadable checkpoint does not fail queue loading")
  func unreadableCheckpointDoesNotFailQueueLoading() async throws {
    let episodes = try await makeEpisodes()
    let firstCheckpoint = TranscriptionCheckpoint(
      segments: [],
      audioTime: 15,
      duration: 60,
      locale: "en-US",
      audioSHA256: FakeAudioFileHasher.defaultSHA256
    )
    let thirdCheckpoint = TranscriptionCheckpoint(
      segments: [],
      audioTime: 45,
      duration: 60,
      locale: "en-US",
      audioSHA256: FakeAudioFileHasher.defaultSHA256
    )
    try await repo.saveTranscriptionCheckpoint(firstCheckpoint, for: episodes[0].id)
    try await repo.saveTranscriptionCheckpoint(firstCheckpoint, for: episodes[1].id)
    try await repo.saveTranscriptionCheckpoint(thirdCheckpoint, for: episodes[2].id)

    let unreadableCheckpoint = """
      {
        "segments": [null],
        "audioTime": 30,
        "duration": 60,
        "locale": "en-US",
        "audioSHA256": "\(FakeAudioFileHasher.defaultSHA256)"
      }
      """
    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          UPDATE episodeTranscriptionCheckpoint
          SET checkpointJSON = ?
          WHERE episodeId = ?
          """,
        arguments: [unreadableCheckpoint, episodes[1].id]
      )
    }
    for episode in episodes {
      try await transcriptionQueue.enqueue(episode.id)
    }

    let viewModel = TranscriptionQueueViewModel()
    let executeTask = Task { await viewModel.execute() }
    defer { executeTask.cancel() }

    try await Wait.until(
      { @MainActor in viewModel.loadingState != .loading },
      { @MainActor in "Expected queue loading to finish" }
    )

    #expect(viewModel.loadingState == .loaded)
    #expect(viewModel.entries.map(\.id) == episodes.map(\.id))
    #expect(viewModel.entries.map(\.progress) == [0.25, 0, 0.75])
  }

  @Test("stale hydration cannot overwrite newer queue membership")
  func staleHydrationCannotOverwriteNewerQueueMembership() async throws {
    let episodes = try await makeEpisodes()
    for episode in episodes {
      try await transcriptionQueue.enqueue(episode.id)
    }
    let episodeIDs = episodes.map(\.id)
    let fakeRepo = try #require(repo as? FakeRepo)
    let viewModel = TranscriptionQueueViewModel()
    let executeTask = Task { await viewModel.execute() }
    defer {
      executeTask.cancel()
      Task { await fakeRepo.resumeAllPodcastEpisodesFetchSuspensions() }
    }

    try await Wait.until(
      { @MainActor in viewModel.entries.map(\.id) == episodeIDs },
      { @MainActor in "Expected initial order, got \(viewModel.entries.map(\.id))" }
    )

    fakeRepo.pendingPodcastEpisodesFetchSuspend(true)
    try await transcriptionQueue.remove(episodes[2].id)
    try await fakeRepo.waitForPodcastEpisodesFetchSuspended()

    try await transcriptionQueue.remove(episodes[1].id)
    #expect(transcriptionQueue.episodeIDs == [episodes[0].id])
    #expect(viewModel.entries.map(\.id) == episodeIDs)

    fakeRepo.pendingPodcastEpisodesFetchSuspend(true)
    await fakeRepo.resumeAllPodcastEpisodesFetchSuspensions()
    try await fakeRepo.waitForPodcastEpisodesFetchSuspended()

    #expect(viewModel.entries.map(\.id) == episodeIDs)
    await fakeRepo.resumeAllPodcastEpisodesFetchSuspensions()

    try await Wait.until(
      { @MainActor in viewModel.entries.map(\.id) == [episodes[0].id] },
      { @MainActor in "Expected latest queue membership" }
    )
  }

  @Test("order-only queue changes reuse loaded rows without another fetch")
  func orderOnlyQueueChangesReuseLoadedRows() async throws {
    let episodes = try await makeEpisodes()
    let checkpoint = TranscriptionCheckpoint(
      segments: [],
      audioTime: 900,
      duration: 3600,
      locale: TranscriptionAvailability.locale.identifier(.bcp47),
      audioSHA256: String(repeating: "c", count: 64)
    )
    try await repo.saveTranscriptionCheckpoint(checkpoint, for: episodes[1].id)
    for episode in episodes {
      try await transcriptionQueue.enqueue(episode.id)
    }
    transcriptionQueue.setProgress(0.42, for: episodes[0].id)

    let fakeRepo = try #require(repo as? FakeRepo)
    let viewModel = TranscriptionQueueViewModel()
    let executeTask = Task { await viewModel.execute() }
    defer {
      fakeRepo.pendingPodcastEpisodesFetchSuspend(false)
      executeTask.cancel()
      Task { await fakeRepo.resumeAllPodcastEpisodesFetchSuspensions() }
    }

    try await Wait.until(
      { @MainActor in viewModel.entries.map(\.id) == episodes.map(\.id) },
      { @MainActor in "Expected initial queue order" }
    )

    fakeRepo.pendingPodcastEpisodesFetchSuspend(true)
    let reorderedEpisodeIDs = [episodes[2].id, episodes[0].id, episodes[1].id]
    #expect(try await transcriptionQueue.reorder(reorderedEpisodeIDs))

    try await Wait.until(
      { @MainActor in viewModel.entries.map(\.id) == reorderedEpisodeIDs },
      { @MainActor in "Order-only queue change started another episode fetch" }
    )

    #expect(fakeRepo.suspendedPodcastEpisodesFetchCount() == 0)
    #expect(viewModel.entries.map(\.progress) == [0, 0.42, 0.25])
  }

  @Test("a drag is rejected when displayed rows no longer match the live queue")
  func staleDragDoesNotMoveDifferentEpisode() async throws {
    try await LogCapture.withSink { sink in
      let episodes = try await makeEpisodes()
      for episode in episodes {
        try await transcriptionQueue.enqueue(episode.id)
      }
      let replacement = try await Create.podcastEpisode(
        try Create.unsavedEpisode(title: "Replacement")
      )
      let initialEpisodeIDs = episodes.map(\.id)

      let viewModel = TranscriptionQueueViewModel()
      let executeTask = Task { await viewModel.execute() }
      defer { executeTask.cancel() }

      try await Wait.until(
        { @MainActor in viewModel.entries.map(\.id) == initialEpisodeIDs },
        { @MainActor in "Expected initial queue order" }
      )

      try await transcriptionQueue.remove(episodes[0].id)
      try await transcriptionQueue.enqueue(replacement.id)
      let liveEpisodeIDs = [episodes[1].id, episodes[2].id, replacement.id]
      #expect(transcriptionQueue.episodeIDs == liveEpisodeIDs)
      #expect(viewModel.entries.map(\.id) == initialEpisodeIDs)

      viewModel.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)

      #expect(transcriptionQueue.episodeIDs == liveEpisodeIDs)
      let rejectionLog = try #require(
        sink.captured()
          .first {
            $0.message.contains("Cannot drag stale transcription queue rows")
          }
      )
      #expect(rejectionLog.level == .notice)
    }
  }

  @Test("queue edits project immediately and serialize overlapping reorders")
  func queueEditsProjectImmediatelyAndSerializeOverlappingReorders() async throws {
    let episodes = try await makeEpisodes()
    let episodeIDs = episodes.map(\.id)
    let firstReorderStarted = AsyncSemaphore(value: 0)
    let firstReorderRelease = AsyncSemaphore(value: 0)
    let reorderCount = ThreadSafe(0)
    let store = FakeTranscriptionQueueStore(
      episodeIDs: episodeIDs,
      beforeReorder: { _ in
        let callCount = reorderCount { count in
          count += 1
          return count
        }
        if callCount == 1 {
          firstReorderStarted.signal()
          await firstReorderRelease.wait()
        }
      }
    )
    Container.shared.transcriptionQueueStore.register { store }
    Container.shared.transcriptionQueue.reset(.scope)
    Container.shared.transcriptionProcessor.reset(.scope)
    let queue = Container.shared.transcriptionQueue()
    await queue.waitUntilLoaded()
    let viewModel = TranscriptionQueueViewModel()
    let executeTask = Task { await viewModel.execute() }
    defer {
      firstReorderRelease.signal()
      executeTask.cancel()
    }

    try await Wait.until(
      { @MainActor in viewModel.entries.map(\.id) == episodeIDs },
      { @MainActor in "Expected initial queue order" }
    )

    let firstOrder = [episodes[1].id, episodes[2].id, episodes[0].id]
    viewModel.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
    #expect(viewModel.entries.map(\.id) == firstOrder)
    await firstReorderStarted.wait()

    let secondOrder = [episodes[2].id, episodes[1].id, episodes[0].id]
    viewModel.move(fromOffsets: IndexSet(integer: 1), toOffset: 0)
    #expect(viewModel.entries.map(\.id) == secondOrder)
    #expect(store.reorderCalls == [firstOrder])

    firstReorderRelease.signal()
    try await Wait.until(
      { @MainActor in queue.episodeIDs == secondOrder },
      { @MainActor in "Expected overlapping reorders to finish in gesture order" }
    )
    #expect(viewModel.entries.map(\.id) == secondOrder)
    #expect(store.reorderCalls == [firstOrder, secondOrder])
  }

  @Test("queued edits finish after the queue manager releases its view model")
  func queuedEditsFinishAfterViewModelRelease() async throws {
    let episodes = try await makeEpisodes()
    let episodeIDs = episodes.map(\.id)
    let firstReorderStarted = AsyncSemaphore(value: 0)
    let firstReorderRelease = AsyncSemaphore(value: 0)
    let reorderCount = ThreadSafe(0)
    let store = FakeTranscriptionQueueStore(
      episodeIDs: episodeIDs,
      beforeReorder: { _ in
        let callCount = reorderCount { count in
          count += 1
          return count
        }
        if callCount == 1 {
          firstReorderStarted.signal()
          await firstReorderRelease.wait()
        }
      }
    )
    Container.shared.transcriptionQueueStore.register { store }
    Container.shared.transcriptionQueue.reset(.scope)
    Container.shared.transcriptionProcessor.reset(.scope)
    let queue = Container.shared.transcriptionQueue()
    await queue.waitUntilLoaded()
    var viewModel: TranscriptionQueueViewModel? = TranscriptionQueueViewModel()
    weak let releasedViewModel = viewModel
    let executeTask = Task { [weak viewModel] in await viewModel?.execute() }
    defer {
      firstReorderRelease.signal()
      executeTask.cancel()
    }

    try await Wait.until(
      { @MainActor in releasedViewModel?.entries.map(\.id) == episodeIDs },
      { @MainActor in "Expected initial queue order" }
    )

    let firstOrder = [episodes[1].id, episodes[2].id, episodes[0].id]
    viewModel?.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
    await firstReorderStarted.wait()

    let secondOrder = [episodes[2].id, episodes[1].id, episodes[0].id]
    viewModel?.move(fromOffsets: IndexSet(integer: 1), toOffset: 0)
    #expect(store.reorderCalls == [firstOrder])

    executeTask.cancel()
    await executeTask.value
    viewModel = nil
    firstReorderRelease.signal()

    try await Wait.until(
      { @MainActor in queue.episodeIDs == secondOrder || releasedViewModel == nil },
      { @MainActor in "Expected the queued reorder to finish or release its owner" }
    )
    #expect(store.reorderCalls == [firstOrder, secondOrder])
    #expect(queue.episodeIDs == secondOrder)
    try await Wait.until(
      { @MainActor in releasedViewModel == nil },
      { @MainActor in "Expected the completed mutation chain to release its view model" }
    )
  }

  @Test("failed removal restores its row and selection")
  func failedRemovalRestoresRowAndSelection() async throws {
    let episodes = try await makeEpisodes()
    let episodeIDs = episodes.map(\.id)
    let removalStarted = AsyncSemaphore(value: 0)
    let removalRelease = AsyncSemaphore(value: 0)
    let store = FakeTranscriptionQueueStore(
      episodeIDs: episodeIDs,
      beforeRemove: { _ in
        removalStarted.signal()
        await removalRelease.wait()
        throw TestError.simulatedFailure
      }
    )
    Container.shared.transcriptionQueueStore.register { store }
    Container.shared.transcriptionQueue.reset(.scope)
    Container.shared.transcriptionProcessor.reset(.scope)
    let queue = Container.shared.transcriptionQueue()
    await queue.waitUntilLoaded()
    let viewModel = TranscriptionQueueViewModel()
    let executeTask = Task { await viewModel.execute() }
    defer {
      removalRelease.signal()
      executeTask.cancel()
    }

    try await Wait.until(
      { @MainActor in viewModel.entries.map(\.id) == episodeIDs },
      { @MainActor in "Expected initial queue order" }
    )
    viewModel.selectedEpisodeIDs = [episodes[1].id]

    viewModel.remove(episodes[1].id)

    #expect(viewModel.entries.map(\.id) == [episodes[0].id, episodes[2].id])
    #expect(viewModel.selectedEpisodeIDs.isEmpty)
    await removalStarted.wait()
    removalRelease.signal()

    let alert = Container.shared.alert()
    try await Wait.until(
      { @MainActor in
        alert.config != nil
          && viewModel.entries.map(\.id) == episodeIDs
          && viewModel.selectedEpisodeIDs == [episodes[1].id]
      },
      { @MainActor in "Expected failed deletion to restore its row and selection" }
    )
    #expect(queue.episodeIDs == episodeIDs)
  }

  @Test("moves a multi-selection while preserving its queue order")
  func movesMultiSelectionInQueueOrder() async throws {
    let episodes = try await makeEpisodes()
    for episode in episodes {
      try await transcriptionQueue.enqueue(episode.id)
    }

    let viewModel = TranscriptionQueueViewModel()
    let executeTask = Task { await viewModel.execute() }
    defer { executeTask.cancel() }
    try await Wait.until(
      { @MainActor in viewModel.entries.map(\.id) == episodes.map(\.id) },
      { @MainActor in "Expected initial queue order" }
    )
    viewModel.selectedEpisodeIDs = [episodes[2].id]
    viewModel.moveSelectedToTop()
    let topOrder = [episodes[2].id, episodes[0].id, episodes[1].id]
    try await Wait.until(
      { @MainActor in self.transcriptionQueue.episodeIDs == topOrder },
      { @MainActor in "Expected selected episodes to move to the top" }
    )

    viewModel.selectedEpisodeIDs = [episodes[2].id, episodes[0].id]
    viewModel.moveSelectedToBottom()
    let bottomOrder = [episodes[1].id, episodes[2].id, episodes[0].id]
    try await Wait.until(
      { @MainActor in self.transcriptionQueue.episodeIDs == bottomOrder },
      { @MainActor in "Expected selected episodes to move to the bottom" }
    )
  }

  @Test("removing a multi-selection retains its partial checkpoints")
  func removesMultiSelectionAndRetainsCheckpoints() async throws {
    let episodes = try await makeEpisodes()
    let checkpoint = TranscriptionCheckpoint(
      segments: [],
      audioTime: 600,
      duration: 3600,
      locale: TranscriptionAvailability.locale.identifier(.bcp47),
      audioSHA256: String(repeating: "b", count: 64)
    )
    for episode in episodes {
      try await repo.saveTranscriptionCheckpoint(checkpoint, for: episode.id)
      try await transcriptionQueue.enqueue(episode.id)
    }

    let viewModel = TranscriptionQueueViewModel()
    let executeTask = Task { await viewModel.execute() }
    defer { executeTask.cancel() }
    try await Wait.until(
      { @MainActor in viewModel.entries.map(\.id) == episodes.map(\.id) },
      { @MainActor in "Expected initial queue order" }
    )
    viewModel.selectedEpisodeIDs = [episodes[0].id, episodes[2].id]
    viewModel.removeSelected()

    try await Wait.until(
      { @MainActor in
        self.transcriptionQueue.episodeIDs == [episodes[1].id]
          && self.transcriptionQueue.interruptions.isEmpty
      },
      { @MainActor in "Expected selected episodes to finish pausing" }
    )
    #expect(viewModel.selectedEpisodeIDs.isEmpty)
    #expect(try await repo.transcriptionCheckpoint(episodes[0].id) == checkpoint)
    #expect(try await repo.transcriptionCheckpoint(episodes[1].id) == checkpoint)
    #expect(try await repo.transcriptionCheckpoint(episodes[2].id) == checkpoint)
  }

  @Test("failed multi-selection removal alerts and remains selected")
  func failedMultiSelectionRemovalAlertsAndRemainsSelected() async throws {
    let episodes = try await makeEpisodes()
    let episodeIDs = episodes.map(\.id)
    let store = FakeTranscriptionQueueStore(
      episodeIDs: episodeIDs,
      beforeRemove: { _ in throw TestError.simulatedFailure }
    )
    Container.shared.transcriptionQueueStore.register { store }
    Container.shared.transcriptionQueue.reset(.scope)
    Container.shared.transcriptionProcessor.reset(.scope)
    let queue = Container.shared.transcriptionQueue()
    await queue.waitUntilLoaded()
    let viewModel = TranscriptionQueueViewModel()
    let executeTask = Task { await viewModel.execute() }
    defer { executeTask.cancel() }
    try await Wait.until(
      { @MainActor in viewModel.entries.map(\.id) == episodeIDs },
      { @MainActor in "Expected initial queue order" }
    )
    viewModel.selectedEpisodeIDs = [episodes[0].id, episodes[2].id]
    let alert = Container.shared.alert()

    viewModel.removeSelected()

    try await Wait.until(
      { @MainActor in alert.config != nil },
      { @MainActor in "Expected queue-removal persistence failure to alert" }
    )
    #expect(queue.episodeIDs == episodeIDs)
    #expect(queue.interruptions.isEmpty)
    #expect(viewModel.selectedEpisodeIDs == [episodes[0].id, episodes[2].id])
  }

  private func makeEpisodes() async throws -> [Episode] {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(title: "Queue Podcast"),
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: "first", title: "First"),
          try Create.unsavedEpisode(guid: "second", title: "Second"),
          try Create.unsavedEpisode(guid: "third", title: "Third"),
        ]
      )
    )
    return Array(series.episodes)
  }
}
