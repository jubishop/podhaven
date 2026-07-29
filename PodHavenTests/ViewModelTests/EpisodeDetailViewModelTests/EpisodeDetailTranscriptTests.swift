// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of EpisodeDetailViewModel transcript", .container)
@MainActor struct EpisodeDetailTranscriptTests {
  @DynamicInjected(\.appDB) private var appDB
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.transcriptionQueue) private var transcriptionQueue

  private var fakeObservatory: FakeObservatory {
    observatory as! FakeObservatory
  }

  private func makeTargetBeyondCapacity() async throws -> PodcastEpisode {
    Container.shared.userSettings().$maxTranscriptionQueueLength.new(10)
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: try (0..<11)
          .map {
            try Create.unsavedEpisode(guid: GUID("detail-capacity-\($0)"))
          }
      )
    )
    try await transcriptionQueue.enqueue(series.episodes.prefix(10).map(\.id))
    return try #require(try await repo.podcastEpisode(series.episodes[10].id))
  }

  @Test("decodedTranscript returns the stored transcript for a transcribed episode")
  func decodedTranscriptReturnsStoredTranscript() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let transcript = Transcript(
      segments: [
        TranscriptSegment(start: 0, end: 1, text: "hello"),
        TranscriptSegment(start: 1, end: 2, text: "world"),
      ],
      locale: "en-US",
      createdAt: Date(timeIntervalSince1970: 0)
    )
    try await repo.updateTranscript(podcastEpisode.id, transcript: transcript.jsonString())

    let loaded = try #require(try await repo.podcastEpisode(podcastEpisode.id))
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(loaded))

    #expect(viewModel.episode.hasTranscript == true)
    #expect(viewModel.decodedTranscript?.segments.map(\.text) == ["hello", "world"])
  }

  @Test("listed initial state preserves transcript status before hydration")
  func listedInitialStatePreservesTranscriptStatus() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let transcript = Transcript(
      segments: [TranscriptSegment(start: 0, end: 1, text: "hello")],
      locale: "en-US",
      createdAt: Date(timeIntervalSince1970: 0)
    )
    try await repo.updateTranscript(podcastEpisode.id, transcript: transcript.jsonString())

    let listableEpisodes =
      try await observatory.listablePodcastEpisodes(
        filter: Episode.Columns.id == podcastEpisode.id
      )
      .get()
    let listedEpisode = try #require(listableEpisodes.first)

    let viewModel = EpisodeDetailViewModel(listedEpisode: ListedEpisode(listedEpisode))

    #expect(listedEpisode.hasTranscript == true)
    #expect(viewModel.episode.hasTranscript == true)
    #expect(viewModel.transcriptionStatus == .transcribed)
    #expect(viewModel.decodedTranscript == nil)
    #expect(viewModel.transcriptDisplay == .loading)
  }

  @Test("transcriptDisplay preserves segments once the episode is hydrated")
  func transcriptDisplayPreservesSegmentsWhenHydrated() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let transcript = Transcript(
      segments: [
        TranscriptSegment(start: 0, end: 1, text: "hello"),
        TranscriptSegment(start: 1, end: 2, text: "world"),
      ],
      locale: "en-US",
      createdAt: Date(timeIntervalSince1970: 0)
    )
    try await repo.updateTranscript(podcastEpisode.id, transcript: transcript.jsonString())

    let loaded = try #require(try await repo.podcastEpisode(podcastEpisode.id))
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(loaded))

    #expect(viewModel.transcriptDisplay == .text(transcript.segments))
  }

  @Test("transcriptDisplay is empty when a hydrated transcript has no segments")
  func transcriptDisplayEmptyForNoSegments() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let transcript = Transcript(
      segments: [],
      locale: "en-US",
      createdAt: Date(timeIntervalSince1970: 0)
    )
    try await repo.updateTranscript(podcastEpisode.id, transcript: transcript.jsonString())

    let loaded = try #require(try await repo.podcastEpisode(podcastEpisode.id))
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(loaded))

    #expect(viewModel.transcriptDisplay == .empty)
    #expect(viewModel.transcriptionStatus == .transcribed)
  }

  @Test("malformed transcript is retryable and cleared before enqueue")
  func malformedTranscriptCanRetry() async throws {
    await TranscriptionHelpers.prepareAvailability()
    let podcastEpisode = try await Create.podcastEpisode()
    try await repo.updateTranscript(podcastEpisode.id, transcript: "not-json")

    let loaded = try #require(try await repo.podcastEpisode(podcastEpisode.id))
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(loaded))

    #expect(viewModel.transcriptDisplay == .decodeFailed)
    #expect(viewModel.transcriptionStatus.canTranscribe)

    viewModel.transcribe()

    try await Wait.until(
      { @MainActor in transcriptionQueue.episodeIDs.contains(podcastEpisode.id) },
      { @MainActor in "Expected malformed transcript to be re-enqueued" }
    )
    let cleared = try #require(try await repo.episode(podcastEpisode.id))
    #expect(!cleared.hasTranscript)
  }

  @Test("detail transcription shows the queue-full alert without error telemetry")
  func detailTranscriptionShowsCapacityAlert() async throws {
    try await LogCapture.withSink { sink in
      await TranscriptionHelpers.prepareAvailability()
      let target = try await makeTargetBeyondCapacity()
      let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(target))
      let alert = Container.shared.alert()

      viewModel.transcribe()

      try await Wait.until(
        { @MainActor in alert.config?.title == "Transcription Queue Full" },
        { @MainActor in "Expected the detail queue-full alert" }
      )
      #expect(transcriptionQueue.episodeIDs.count == 10)
      #expect(!transcriptionQueue.episodeIDs.contains(target.id))
      let rejectionLog = try #require(
        sink.captured()
          .first {
            $0.message.contains("transcribe:") && $0.message.contains("rejected")
          }
      )
      #expect(rejectionLog.level == .notice)
    }
  }

  @Test("detail pause removes a queued transcription")
  func detailPauseRemovesQueuedTranscription() async throws {
    await TranscriptionHelpers.prepareAvailability()
    let podcastEpisode = try await Create.podcastEpisode()
    try await transcriptionQueue.enqueue(podcastEpisode.id)
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(podcastEpisode))

    #expect(viewModel.transcriptionStatus.canPause)

    viewModel.pauseTranscription()

    try await Wait.until(
      { @MainActor in viewModel.transcriptionStatus == .none },
      { @MainActor in "Expected queued pause to finish" }
    )
    #expect(!transcriptionQueue.episodeIDs.contains(podcastEpisode.id))
  }

  @Test("detail pause reports a durable queue-removal failure")
  func detailPauseReportsQueueRemovalFailure() async throws {
    await TranscriptionHelpers.prepareAvailability()
    let podcastEpisode = try await Create.podcastEpisode()
    let store = FakeTranscriptionQueueStore(
      episodeIDs: [podcastEpisode.id],
      beforeRemove: { _ in throw TestError.simulatedFailure }
    )
    Container.shared.transcriptionQueueStore.register { store }
    Container.shared.transcriptionQueue.reset(.scope)
    Container.shared.transcriptionProcessor.reset(.scope)
    let queue = Container.shared.transcriptionQueue()
    await queue.waitUntilLoaded()
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(podcastEpisode))
    let alert = Container.shared.alert()

    viewModel.pauseTranscription()

    try await Wait.until(
      { @MainActor in alert.config != nil },
      { @MainActor in "Expected pause persistence failure to alert" }
    )
    #expect(queue.episodeIDs == [podcastEpisode.id])
    #expect(queue.interruptions.isEmpty)
  }

  @Test("detail discard reports a durable queue-removal failure")
  func detailDiscardReportsQueueRemovalFailure() async throws {
    await TranscriptionHelpers.prepareAvailability()
    let podcastEpisode = try await Create.podcastEpisode()
    let store = FakeTranscriptionQueueStore(
      episodeIDs: [podcastEpisode.id],
      beforeRemove: { _ in throw TestError.simulatedFailure }
    )
    Container.shared.transcriptionQueueStore.register { store }
    Container.shared.transcriptionQueue.reset(.scope)
    Container.shared.transcriptionProcessor.reset(.scope)
    let queue = Container.shared.transcriptionQueue()
    await queue.waitUntilLoaded()
    queue.setProgress(0.5, for: podcastEpisode.id)
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(podcastEpisode))
    let alert = Container.shared.alert()

    viewModel.discardTranscriptionProgress()

    try await Wait.until(
      { @MainActor in alert.config != nil },
      { @MainActor in "Expected discard persistence failure to alert" }
    )
    #expect(queue.episodeIDs == [podcastEpisode.id])
    #expect(queue.progress[podcastEpisode.id] == 0.5)
    #expect(queue.interruptions.isEmpty)
  }

  @Test("detail pause retains partial transcription progress")
  func detailPauseRetainsPartialProgress() async throws {
    await TranscriptionHelpers.prepareAvailability()
    let podcastEpisode = try await Create.podcastEpisode()
    let checkpoint = TranscriptionCheckpoint(
      segments: [TranscriptSegment(start: 0, end: 30, text: "partial")],
      audioTime: 30,
      duration: 60,
      locale: "en-US",
      audioSHA256: FakeAudioFileHasher.defaultSHA256
    )
    try await repo.saveTranscriptionCheckpoint(checkpoint, for: podcastEpisode.id)
    try await transcriptionQueue.enqueue(podcastEpisode.id)
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(podcastEpisode))

    viewModel.pauseTranscription()

    try await Wait.until(
      { @MainActor in
        !self.transcriptionQueue.episodeIDs.contains(podcastEpisode.id)
          && self.transcriptionQueue.interruptions[podcastEpisode.id] == nil
      },
      { @MainActor in "Expected queued progress to finish pausing" }
    )
    #expect(transcriptionQueue.interruptions[podcastEpisode.id] == nil)
    #expect(try await repo.transcriptionCheckpoint(podcastEpisode.id) == checkpoint)
  }

  @Test("detail resumes retained progress and discards it only on explicit request")
  func detailResumesAndExplicitlyDiscardsProgress() async throws {
    await TranscriptionHelpers.prepareAvailability()
    let podcastEpisode = try await Create.podcastEpisode()
    let checkpoint = TranscriptionCheckpoint(
      segments: [TranscriptSegment(start: 0, end: 30, text: "partial")],
      audioTime: 30,
      duration: 60,
      locale: "en-US",
      audioSHA256: FakeAudioFileHasher.defaultSHA256
    )
    try await repo.saveTranscriptionCheckpoint(checkpoint, for: podcastEpisode.id)
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(podcastEpisode))
    viewModel.appear()
    defer { viewModel.disappear() }

    try await Wait.until(
      { @MainActor in viewModel.transcriptionStatus == .paused(0.5) },
      { @MainActor in "Expected saved progress to appear as paused" }
    )
    #expect(viewModel.transcriptionStatus.canTranscribe)
    #expect(viewModel.canDiscardTranscriptionProgress)

    viewModel.transcribe()
    let resumedEpisodeIDs = await TranscriptionHelpers.waitForQueuedEpisode(
      podcastEpisode.id,
      in: transcriptionQueue
    )
    #expect(resumedEpisodeIDs.contains(podcastEpisode.id))
    #expect(viewModel.transcriptionStatus.canPause)

    viewModel.pauseTranscription()
    try await Wait.until(
      { @MainActor in viewModel.transcriptionStatus == .paused(0.5) },
      { @MainActor in "Expected resumed work to finish pausing" }
    )

    viewModel.discardTranscriptionProgress()
    try await Wait.until(
      {
        try await self.repo.transcriptionCheckpoint(podcastEpisode.id) == nil
      },
      { "Expected explicit discard to delete saved progress" }
    )
    try await Wait.until(
      { @MainActor in viewModel.transcriptionStatus == .none },
      { @MainActor in "Expected detail to return to an untranscribed state" }
    )
  }

  @Test("decodedTranscript follows observed updates for the same episode")
  func decodedTranscriptFollowsObservedUpdates() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let original = Transcript(
      segments: [TranscriptSegment(start: 0, end: 1, text: "original")],
      locale: "en-US",
      createdAt: Date(timeIntervalSince1970: 0)
    )
    try await repo.updateTranscript(podcastEpisode.id, transcript: original.jsonString())

    let loaded = try #require(try await repo.podcastEpisode(podcastEpisode.id))
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(loaded))
    viewModel.appear()
    defer { viewModel.disappear() }

    #expect(viewModel.decodedTranscript?.segments.map(\.text) == ["original"])
    try await Wait.until(
      { @MainActor in
        fakeObservatory.allCallsInOrder.contains { $0.methodName == "podcastEpisodeWithTags" }
      },
      { @MainActor in "Expected episode observation to start" }
    )

    let replacement = Transcript(
      segments: [TranscriptSegment(start: 0, end: 1, text: "replacement")],
      locale: "en-US",
      createdAt: Date(timeIntervalSince1970: 1)
    )
    try await repo.updateTranscript(podcastEpisode.id, transcript: replacement.jsonString())

    try await Wait.until(
      { @MainActor in
        viewModel.decodedTranscript?.segments.map(\.text) == ["replacement"]
      },
      { @MainActor in
        "Expected replacement transcript, got \(String(describing: viewModel.decodedTranscript))"
      }
    )
  }

  @Test("checkpoint observation failure clears progress without stopping episode updates")
  func checkpointObservationFailureClearsProgressWithoutStoppingEpisodeUpdates() async throws {
    try await LogCapture.withSink { sink in
      let podcastEpisode = try await Create.podcastEpisode()
      let checkpoint = TranscriptionCheckpoint(
        segments: [TranscriptSegment(start: 0, end: 30, text: "partial")],
        audioTime: 30,
        duration: 60,
        locale: "en-US",
        audioSHA256: FakeAudioFileHasher.defaultSHA256
      )
      try await repo.saveTranscriptionCheckpoint(checkpoint, for: podcastEpisode.id)
      let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(podcastEpisode))
      viewModel.appear()
      defer { viewModel.disappear() }

      try await Wait.until(
        { @MainActor in viewModel.transcriptionStatus == .paused(0.5) },
        { @MainActor in "Expected saved progress to appear as paused" }
      )

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
          arguments: [unreadableCheckpoint, podcastEpisode.id]
        )
      }

      try await Wait.until(
        {
          sink.captured()
            .contains {
              $0.message.contains("observeTranscriptionCheckpoint: observation failed")
            }
        },
        { "Expected the checkpoint observation to fail" }
      )
      try await yieldForSpuriousAsyncWork()
      #expect(viewModel.transcriptionCheckpointProgress == nil)
      #expect(viewModel.transcriptionStatus == .none)

      let transcript = Transcript(
        segments: [TranscriptSegment(start: 0, end: 1, text: "still observed")],
        locale: "en-US",
        createdAt: Date(timeIntervalSince1970: 0)
      )
      try await repo.updateTranscript(podcastEpisode.id, transcript: transcript.jsonString())

      try await Wait.until(
        { @MainActor in
          viewModel.decodedTranscript?.segments.map(\.text) == ["still observed"]
        },
        { @MainActor in
          """
          Expected episode updates after the checkpoint observation failed, got \
          \(String(describing: viewModel.decodedTranscript))
          """
        }
      )
    }
  }

  @Test("detail text defaults to description and switches to transcript")
  func detailTextSelection() async throws {
    await TranscriptionHelpers.prepareAvailability()
    let podcastEpisode = try await Create.podcastEpisode()
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(podcastEpisode))

    #expect(viewModel.selectedTextTab == .description)

    viewModel.selectTextTab(.transcript)

    #expect(viewModel.selectedTextTab == .transcript)
  }

  @Test("detail transcription stays hidden and inert while support is unknown")
  func detailTranscriptionHiddenWhileSupportUnknown() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(podcastEpisode))

    #expect(!viewModel.isTranscriptionAvailable)

    viewModel.selectTextTab(.transcript)
    viewModel.transcribe()

    #expect(viewModel.selectedTextTab == .description)
    #expect(!transcriptionQueue.episodeIDs.contains(podcastEpisode.id))
  }
}
