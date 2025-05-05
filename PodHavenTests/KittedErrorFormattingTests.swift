// Copyright Justin Bishop, 2025

import AVFoundation
import Factory
import Foundation
import Testing

@testable import PodHaven

enum FakeFormattedError: KittedError {
  case doubleFailure(one: Error, two: Error)
  case failure(underlying: Error)
  case leaf
  case leafUnderlying(underlying: Error)
  case simple(String)
  case caught(Error)

  var userFriendlyMessage: String {
    switch self {
    case .doubleFailure(let one, let two):
      return
        """
        Failure
          One: \(Self.nestedUserFriendlyMessage(for: one))
          Two: \(Self.nestedUserFriendlyMessage(for: two))
        Done
        """
    case .failure(let underlying):
      return
        """
        Failure
          \(Self.nestedUserFriendlyMessage(for: underlying))
        """
    case .leaf:
      return
        """
        Leaf
        Line Two
          Indented Line
        """
    case .leafUnderlying(let underlying):
      return
        """
        Leaf
        Wrapping:
          \(Self.nestedUserFriendlyMessage(for: underlying))
        """
    case .simple(let message):
      return message
    case .caught(let error):
      return nestedUserFriendlyCaughtMessage(error)
    }
  }
}

@Suite("of KittedError formatting tests")
struct KittedErrorFormattingTests {
  private let repo: Repo = .inMemory()

  @Test("messages with caught generic at end")
  func testMessagesCaughtGenericAtEnd() {
    let error = FakeFormattedError.failure(
      underlying: FakeFormattedError.failure(
        underlying: FakeFormattedError.failure(
          underlying: FakeFormattedError.caught(
            FakeFormattedError.simple("Generic edge case")
          )
        )
      )
    )

    #expect(
      error.userFriendlyMessage == """
        Failure
          Failure
            Failure
              FakeFormattedError ->
                Generic edge case
        """
    )
  }

  @Test("messages with caught kitted at end")
  func testMessagesCaughtKittedAtEnd() {
    let error = FakeFormattedError.failure(
      underlying: FakeFormattedError.failure(
        underlying: FakeFormattedError.failure(
          underlying: FakeFormattedError.caught(
            FakeFormattedError.leaf
          )
        )
      )
    )

    #expect(
      error.userFriendlyMessage == """
        Failure
          Failure
            Failure
              FakeFormattedError ->
                Leaf
                Line Two
                  Indented Line
        """
    )
  }

  @Test("messages with caught kitted in middle")
  func testFormattingNestedUserFriendlyMessagesKittedAtEnd() {
    let error = FakeFormattedError.failure(
      underlying: FakeFormattedError.failure(
        underlying: FakeFormattedError.failure(
          underlying: FakeFormattedError.caught(
            FakeFormattedError.failure(
              underlying: FakeFormattedError.failure(
                underlying: FakeFormattedError.leafUnderlying(
                  underlying: FakeFormattedError.simple("Generic edge case")
                )
              )
            )
          )
        )
      )
    )

    #expect(
      error.userFriendlyMessage == """
        Failure
          Failure
            Failure
              FakeFormattedError ->
                Failure
                  Failure
                    Leaf
                    Wrapping:
                      Generic edge case
        """
    )
  }

  @Test("messages with double failure")
  func testFormattingDoubleFailure() {
    let error = FakeFormattedError.failure(
      underlying: FakeFormattedError.failure(
        underlying: FakeFormattedError.doubleFailure(
          one: FakeFormattedError.caught(
            FakeFormattedError.failure(
              underlying: FakeFormattedError.failure(
                underlying: FakeFormattedError.leafUnderlying(
                  underlying: FakeFormattedError.simple(
                    """
                    Generic edge case
                    Heyo
                      Indented
                    """
                  )
                )
              )
            )
          ),
          two: FakeFormattedError.failure(
            underlying: FakeFormattedError.failure(
              underlying: FakeFormattedError.leaf
            )
          )
        )
      )
    )

    #expect(
      error.userFriendlyMessage == """
        Failure
          Failure
            Failure
              One: FakeFormattedError ->
                Failure
                  Failure
                    Leaf
                    Wrapping:
                      Generic edge case
                      Heyo
                        Indented
              Two: Failure
                Failure
                  Leaf
                  Line Two
                    Indented Line
            Done
        """
    )
  }

  @Test("playback error media not playable formatting")
  func testPlaybackErrorMediaNotPlayableFormatting() async throws {
    let url = URL(string: "https://example.com/data")!
    let episodeTitle = "Test Episode"
    let unsavedPodcast = try TestHelpers.unsavedPodcast()
    let unsavedEpisode = try TestHelpers.unsavedEpisode(media: MediaURL(url), title: episodeTitle)
    let podcastSeries = try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [unsavedEpisode]
    )
    let podcastEpisode = PodcastEpisode(
      podcast: podcastSeries.podcast,
      episode: podcastSeries.episodes.first!
    )
    let error = FakeFormattedError.failure(
      underlying: FakeFormattedError.caught(
        PlaybackError.mediaNotPlayable(podcastEpisode)
      )
    )
    #expect(
      error.userFriendlyMessage == """
        Failure
          FakeFormattedError ->
            MediaURL Not Playable
              PodcastEpisode: Test Episode
              MediaURL: https://example.com/data
        """
    )
  }

  @Test("search error fetch failure formatting")
  func testSearchErrorFetchFailureFormatting() async throws {
    let error = SearchError.fetchFailure(
      request: URLRequest(url: URL(string: "https://example.com/search")!),
      caught: FakeFormattedError.simple("Failed to fetch")
    )
    #expect(
      error.userFriendlyMessage == """
        Failed to fetch url: https://example.com/search ->
        Caught ->
          Failed to fetch
        """
    )
  }
}
