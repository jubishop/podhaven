// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("of PodcastDetailViewModel transcription", .container)
@MainActor struct PodcastDetailTranscriptionTests {
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.transcriptionQueue) private var transcriptionQueue

  @Test("bulk transcription resolves a saved selection with one batch fetch")
  func bulkTranscriptionResolvesSavedSelectionOnce() async throws {
    await TranscriptionHelpers.prepareAvailability()
    let savedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(title: "Saved Transcription"),
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: "transcribe-saved-1", title: "Episode 1"),
          try Create.unsavedEpisode(guid: "transcribe-saved-2", title: "Episode 2"),
          try Create.unsavedEpisode(guid: "transcribe-saved-3", title: "Episode 3"),
        ]
      )
    )
    let viewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(savedSeries.podcast))
    try await PodcastDetailTestHelpers.appear(viewModel)
    try await Wait.until(
      { @MainActor in viewModel.episodeList.allEntries.count == 3 },
      { @MainActor in
        "Expected all saved episodes before selection; count=\(viewModel.episodeList.allEntries.count)"
      }
    )

    let selectedEpisodes = Array(savedSeries.episodes.prefix(2))
    try PodcastDetailTestHelpers.select(
      viewModel,
      episodeIDs: selectedEpisodes.map(\.id)
    )
    #expect(viewModel.selectedEpisodes.count == 2)

    let fakeRepo = try #require(repo as? FakeRepo)
    fakeRepo.clearAllCalls()
    viewModel.disappear()

    viewModel.transcribeSelectedEpisodes()

    try await Wait.until(
      { @MainActor in self.transcriptionQueue.episodeIDs.count == selectedEpisodes.count },
      { @MainActor in
        "Expected selected episodes to be queued; queue=\(self.transcriptionQueue.episodeIDs)"
      }
    )

    _ = try fakeRepo.expectCalls(methodName: "podcastEpisodes", count: 1)
    try fakeRepo.expectNoCall(methodName: "podcastEpisode")
    #expect(Set(transcriptionQueue.episodeIDs) == Set(selectedEpisodes.map(\.id)))
  }
}
