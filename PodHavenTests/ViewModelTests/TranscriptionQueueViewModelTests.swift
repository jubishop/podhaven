// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
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
      transcriptionQueue.enqueue(episode.id)
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
  }

  @Test("queued checkpoint progress is announced as waiting")
  func queuedCheckpointProgressIsAnnouncedAsWaiting() async throws {
    let episode = try await Create.podcastEpisode()
    let entry = TranscriptionQueueViewModel.Entry(
      episode: episode,
      progress: 0.25,
      isActive: false
    )

    #expect(entry.statusText == "Waiting · 25%")
    #expect(entry.accessibilityValue == "Waiting, 25 percent complete")
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
      transcriptionQueue.enqueue(episode.id)
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
      transcriptionQueue.enqueue(episode.id)
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
    transcriptionQueue.remove(episodes[2].id)
    try await fakeRepo.waitForPodcastEpisodesFetchSuspended()

    transcriptionQueue.remove(episodes[1].id)
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
      transcriptionQueue.enqueue(episode.id)
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
    #expect(transcriptionQueue.reorder(reorderedEpisodeIDs))

    try await Wait.until(
      { @MainActor in viewModel.entries.map(\.id) == reorderedEpisodeIDs },
      { @MainActor in "Order-only queue change started another episode fetch" }
    )

    #expect(fakeRepo.suspendedPodcastEpisodesFetchCount() == 0)
    #expect(viewModel.entries.map(\.progress) == [0, 0.42, 0.25])
  }

  @Test("moves a multi-selection while preserving its queue order")
  func movesMultiSelectionInQueueOrder() async throws {
    let episodes = try await makeEpisodes()
    for episode in episodes {
      transcriptionQueue.enqueue(episode.id)
    }

    let viewModel = TranscriptionQueueViewModel()
    viewModel.selectedEpisodeIDs = [episodes[2].id]
    viewModel.moveSelectedToTop()
    #expect(
      transcriptionQueue.episodeIDs
        == [episodes[2].id, episodes[0].id, episodes[1].id]
    )

    viewModel.selectedEpisodeIDs = [episodes[2].id, episodes[0].id]
    viewModel.moveSelectedToBottom()
    #expect(
      transcriptionQueue.episodeIDs
        == [episodes[1].id, episodes[2].id, episodes[0].id]
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
      transcriptionQueue.enqueue(episode.id)
    }

    let viewModel = TranscriptionQueueViewModel()
    viewModel.selectedEpisodeIDs = [episodes[0].id, episodes[2].id]
    viewModel.removeSelected()

    #expect(transcriptionQueue.episodeIDs == [episodes[1].id])
    #expect(viewModel.selectedEpisodeIDs.isEmpty)
    #expect(transcriptionQueue.interruptions.isEmpty)
    #expect(try await repo.transcriptionCheckpoint(episodes[0].id) == checkpoint)
    #expect(try await repo.transcriptionCheckpoint(episodes[1].id) == checkpoint)
    #expect(try await repo.transcriptionCheckpoint(episodes[2].id) == checkpoint)
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
