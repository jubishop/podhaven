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
        TranscriptSegment(start: 0, text: "hello"),
        TranscriptSegment(start: 1, text: "world"),
      ],
      locale: "en-US",
      createdAt: Date(timeIntervalSince1970: 0),
      modelRevision: Transcriber.recipeVersion
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
      segments: [TranscriptSegment(start: 0, text: "hello")],
      locale: "en-US",
      createdAt: Date(timeIntervalSince1970: 0),
      modelRevision: Transcriber.recipeVersion
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

  @Test("transcriptDisplay joins segment text once the episode is hydrated")
  func transcriptDisplayRendersTextWhenHydrated() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let transcript = Transcript(
      segments: [
        TranscriptSegment(start: 0, text: "hello"),
        TranscriptSegment(start: 1, text: "world"),
      ],
      locale: "en-US",
      createdAt: Date(timeIntervalSince1970: 0),
      modelRevision: Transcriber.recipeVersion
    )
    try await repo.updateTranscript(podcastEpisode.id, transcript: transcript.jsonString())

    let loaded = try #require(try await repo.podcastEpisode(podcastEpisode.id))
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(loaded))

    #expect(viewModel.transcriptDisplay == .text("hello\nworld"))
  }

  @Test("transcriptDisplay is empty when a hydrated transcript has no segments")
  func transcriptDisplayEmptyForNoSegments() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let transcript = Transcript(
      segments: [],
      locale: "en-US",
      createdAt: Date(timeIntervalSince1970: 0),
      modelRevision: Transcriber.recipeVersion
    )
    try await repo.updateTranscript(podcastEpisode.id, transcript: transcript.jsonString())

    let loaded = try #require(try await repo.podcastEpisode(podcastEpisode.id))
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(loaded))

    #expect(viewModel.transcriptDisplay == .empty)
    #expect(viewModel.transcriptionStatus == .transcribed)
  }

  @Test("malformed transcript is retryable and cleared before enqueue")
  func malformedTranscriptCanRetry() async throws {
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

  @Test("decodedTranscript follows observed updates for the same episode")
  func decodedTranscriptFollowsObservedUpdates() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let original = Transcript(
      segments: [TranscriptSegment(start: 0, text: "original")],
      locale: "en-US",
      createdAt: Date(timeIntervalSince1970: 0),
      modelRevision: Transcriber.recipeVersion
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
      segments: [TranscriptSegment(start: 0, text: "replacement")],
      locale: "en-US",
      createdAt: Date(timeIntervalSince1970: 1),
      modelRevision: Transcriber.recipeVersion
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
    let podcastEpisode = try await Create.podcastEpisode()
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(podcastEpisode))

    #expect(viewModel.selectedTextTab == .description)

    viewModel.selectTextTab(.transcript)

    #expect(viewModel.selectedTextTab == .transcript)
  }
}
