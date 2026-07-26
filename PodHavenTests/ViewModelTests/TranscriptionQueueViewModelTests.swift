// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("of TranscriptionQueueViewModel tests", .container)
@MainActor final class TranscriptionQueueViewModelTests {
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
