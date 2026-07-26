// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of EpisodeDetailViewModel transcript", .container)
@MainActor struct EpisodeDetailTranscriptTests {
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.transcriptionQueue) private var transcriptionQueue

  private var fakeObservatory: FakeObservatory {
    observatory as! FakeObservatory
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

  @Test("detail pause removes a queued transcription")
  func detailPauseRemovesQueuedTranscription() async throws {
    await TranscriptionHelpers.prepareAvailability()
    let podcastEpisode = try await Create.podcastEpisode()
    transcriptionQueue.enqueue(podcastEpisode.id)
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(podcastEpisode))

    #expect(viewModel.transcriptionStatus.canPause)

    viewModel.pauseTranscription()

    #expect(!transcriptionQueue.episodeIDs.contains(podcastEpisode.id))
    try await Wait.until(
      { @MainActor in viewModel.transcriptionStatus == .none },
      { @MainActor in "Expected queued pause to finish" }
    )
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
    transcriptionQueue.enqueue(podcastEpisode.id)
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(podcastEpisode))

    viewModel.pauseTranscription()

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
    try await Wait.until(
      { @MainActor in
        guard case .queued = viewModel.transcriptionStatus else { return false }
        return true
      },
      { @MainActor in "Expected paused transcription to resume into the queue" }
    )

    viewModel.pauseTranscription()
    #expect(viewModel.transcriptionStatus == .paused(0.5))

    viewModel.discardTranscriptionProgress()
    #expect(viewModel.transcriptionStatus == .discarding)
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
