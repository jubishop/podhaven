// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@MainActor
@Suite("of EpisodesListViewModel transcribe gating", .container)
struct EpisodesListTranscribeTests {
  private var repo: any Databasing { Container.shared.repo() }
  private var transcriptionQueue: TranscriptionQueue { Container.shared.transcriptionQueue() }

  private func transcriptJSON() throws -> String {
    try Transcript(
      segments: [TranscriptSegment(start: 0, text: "hi")],
      locale: "en-US",
      createdAt: Date(timeIntervalSince1970: 0),
      modelRevision: Transcriber.recipeVersion
    ).jsonString()
  }

  // Four episodes ordered transcribed / queued / transcribing / none, returned
  // as the VM's loaded list-row snapshots so `hasTranscript` is current.
  private func makeLoadedViewModel() async throws -> (EpisodesListViewModel, [ListablePodcastEpisode])
  {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: "transcribed"),
          try Create.unsavedEpisode(guid: "queued"),
          try Create.unsavedEpisode(guid: "transcribing"),
          try Create.unsavedEpisode(guid: "none"),
        ]
      )
    )
    let episodes = series.episodes

    try await repo.updateTranscript(episodes[0].id, transcript: transcriptJSON())
    transcriptionQueue.enqueue(episodes[1].id)
    transcriptionQueue.setProgress(0.5, for: episodes[2].id)

    let listables = try await repo.db.read { db in
      try ListablePodcastEpisode
        .request(filter: AppDB.noOp, order: Episode.Columns.id.asc)
        .fetchAll(db)
    }
    let viewModel = try await EpisodesListTestHelpers.makeViewModel(title: "Transcribe")
    try await EpisodesListTestHelpers.loadEntries(into: viewModel, episodes: listables)
    return (viewModel, listables)
  }

  @Test("canTranscribe allows only untranscribed, non-in-flight episodes")
  func canTranscribeReflectsStatus() async throws {
    let (viewModel, listables) = try await makeLoadedViewModel()

    #expect(viewModel.canTranscribe(listables[0]) == false)  // transcribed
    #expect(viewModel.canTranscribe(listables[1]) == false)  // queued
    #expect(viewModel.canTranscribe(listables[2]) == false)  // transcribing
    #expect(viewModel.canTranscribe(listables[3]) == true)  // none
  }

  @Test("anySelectedCanTranscribe is true only when a selected episode can transcribe")
  func anySelectedCanTranscribeReflectsSelection() async throws {
    let (viewModel, listables) = try await makeLoadedViewModel()

    EpisodesListTestHelpers.select(
      viewModel,
      ids: [listables[0].id, listables[1].id, listables[2].id]
    )
    #expect(viewModel.anySelectedCanTranscribe == false)

    EpisodesListTestHelpers.select(viewModel, ids: [listables[3].id])
    #expect(viewModel.anySelectedCanTranscribe == true)
  }
}
