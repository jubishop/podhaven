// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

@MainActor
@Suite("of EpisodesListViewModel transcribe gating", .container)
struct EpisodesListTranscribeTests {
  private var repo: any Databasing { Container.shared.repo() }
  private var transcriptionQueue: TranscriptionQueue { Container.shared.transcriptionQueue() }

  private func transcriptJSON() throws -> String {
    try Transcript(
      segments: [TranscriptSegment(start: 0, end: 1, text: "hi")],
      locale: "en-US",
      createdAt: Date(timeIntervalSince1970: 0)
    )
    .jsonString()
  }

  private func makeCapacityViewModel() async throws -> (
    EpisodesListViewModel, [ListablePodcastEpisode]
  ) {
    await TranscriptionHelpers.prepareAvailability()
    Container.shared.userSettings().$maxTranscriptionQueueLength.new(10)
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: try (0..<12)
          .map {
            try Create.unsavedEpisode(guid: GUID("list-capacity-\($0)"))
          }
      )
    )
    try await transcriptionQueue.enqueue(series.episodes.prefix(10).map(\.id))
    let listables = try await repo.db.read { db in
      try ListablePodcastEpisode
        .request(
          filter: Episode.Columns.podcastId == series.podcast.id,
          order: Episode.Columns.id.asc
        )
        .fetchAll(db)
    }
    let viewModel = try await EpisodesListTestHelpers.makeViewModel(
      title: "Capacity"
    )
    try await EpisodesListTestHelpers.loadEntries(
      into: viewModel,
      episodes: listables
    )
    return (viewModel, listables)
  }

  // Four episodes ordered transcribed / queued / transcribing / none, returned
  // as the VM's loaded list-row snapshots so `hasTranscript` is current.
  private func makeLoadedViewModel(transcriptionAvailable: Bool = true) async throws -> (
    EpisodesListViewModel, [ListablePodcastEpisode]
  ) {
    if transcriptionAvailable {
      await TranscriptionHelpers.prepareAvailability()
    }
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
    try await transcriptionQueue.enqueue(episodes[1].id)
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

  @Test("transcription actions stay hidden and inert while support is unknown")
  func transcriptionHiddenWhileSupportUnknown() async throws {
    let (viewModel, listables) = try await makeLoadedViewModel(transcriptionAvailable: false)
    let eligible = listables[3]

    EpisodesListTestHelpers.select(viewModel, ids: [eligible.id])

    #expect(!viewModel.canTranscribe(eligible))
    #expect(!viewModel.anySelectedCanTranscribe)

    viewModel.transcribeEpisode(eligible)
    viewModel.transcribeSelectedEpisodes()

    #expect(!transcriptionQueue.episodeIDs.contains(eligible.id))
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

  @Test("transcribeSelectedEpisodes enqueues only selected episodes that can transcribe")
  func transcribeSelectedEpisodesFiltersIneligibleSelection() async throws {
    let (viewModel, listables) = try await makeLoadedViewModel()
    let queuedID = listables[1].id
    let eligibleID = listables[3].id

    EpisodesListTestHelpers.select(
      viewModel,
      ids: listables.map(\.id)
    )
    viewModel.transcribeSelectedEpisodes()

    try await Wait.until(
      { @MainActor in transcriptionQueue.episodeIDs.contains(eligibleID) },
      { @MainActor in
        "eligible episode was not queued: \(transcriptionQueue.episodeIDs)"
      }
    )

    #expect(transcriptionQueue.episodeIDs == [queuedID, eligibleID])
  }

  @Test("single transcription shows the queue-full alert without error telemetry")
  func singleTranscriptionShowsCapacityAlert() async throws {
    try await LogCapture.withSink { sink in
      let (viewModel, listables) = try await makeCapacityViewModel()
      let target = listables[10]
      let alert = Container.shared.alert()

      viewModel.transcribeEpisode(target)

      try await Wait.until(
        { @MainActor in alert.config?.title == "Transcription Queue Full" },
        { @MainActor in "Expected the shared single-episode queue-full alert" }
      )
      #expect(transcriptionQueue.episodeIDs.count == 10)
      #expect(!transcriptionQueue.episodeIDs.contains(target.id))
      let rejectionLog = try #require(
        sink.captured()
          .first {
            $0.message.contains("transcribeEpisode: rejected")
          }
      )
      #expect(rejectionLog.level == .notice)
    }
  }

  @Test("bulk transcription shows the queue-full alert without error telemetry")
  func bulkTranscriptionShowsCapacityAlertAtomically() async throws {
    try await LogCapture.withSink { sink in
      let (viewModel, listables) = try await makeCapacityViewModel()
      let targets = Array(listables.suffix(2))
      let alert = Container.shared.alert()
      EpisodesListTestHelpers.select(viewModel, ids: targets.map(\.id))

      viewModel.transcribeSelectedEpisodes()

      try await Wait.until(
        { @MainActor in alert.config?.title == "Transcription Queue Full" },
        { @MainActor in "Expected the bulk queue-full alert" }
      )
      #expect(transcriptionQueue.episodeIDs.count == 10)
      #expect(
        targets.allSatisfy {
          !transcriptionQueue.episodeIDs.contains($0.id)
        }
      )
      let rejectionLog = try #require(
        sink.captured()
          .first {
            $0.message.contains("transcribeSelectedEpisodes: rejected")
          }
      )
      #expect(rejectionLog.level == .notice)
    }
  }

  @Test("transcribeSelectedEpisodes distinguishes identical media across podcasts")
  func transcribeSelectedEpisodesScopesEligibilityToPodcast() async throws {
    await TranscriptionHelpers.prepareAvailability()
    let sharedGUID = GUID("shared-guid")
    let sharedMediaURL = MediaURL(URL.valid())
    let transcribedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(title: "Transcribed Podcast"),
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: sharedGUID, mediaURL: sharedMediaURL)
        ]
      )
    )
    let eligibleSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(title: "Eligible Podcast"),
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: sharedGUID, mediaURL: sharedMediaURL)
        ]
      )
    )
    let transcribedID = transcribedSeries.episodes[0].id
    let eligibleID = eligibleSeries.episodes[0].id
    try await repo.updateTranscript(transcribedID, transcript: transcriptJSON())

    let listables = try await repo.db.read { db in
      try ListablePodcastEpisode
        .request(filter: AppDB.noOp, order: Episode.Columns.id.asc)
        .fetchAll(db)
    }
    let viewModel = try await EpisodesListTestHelpers.makeViewModel(title: "Transcribe")
    try await EpisodesListTestHelpers.loadEntries(into: viewModel, episodes: listables)
    EpisodesListTestHelpers.select(viewModel, ids: listables.map(\.id))

    viewModel.transcribeSelectedEpisodes()

    try await Wait.until(
      { @MainActor in transcriptionQueue.episodeIDs.contains(eligibleID) },
      { @MainActor in
        "eligible episode was not queued: \(transcriptionQueue.episodeIDs)"
      }
    )

    #expect(transcriptionQueue.episodeIDs == [eligibleID])
  }
}
