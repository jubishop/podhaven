// Copyright Justin Bishop, 2025

import AVFoundation
import ErrorKit
import Factory
import Foundation
import Testing

@testable import PodHaven

enum FakeFormattedError: KittedError {
  case doubleFailure(one: any KittedError, two: any KittedError)
  case failure(underlying: any KittedError)
  case leaf
  case leafUnderlying(underlying: Error)
  case caught(Error)

  var nestableUserFriendlyMessage: String {
    switch self {
    case .doubleFailure(let one, let two):
      return
        """
        Failure
          One: \(one.nestedUserFriendlyMessage())
          Two: \(two.nestedUserFriendlyMessage())
        """
    case .failure(let underlying):
      return
        """
        Failure
          \(underlying.nestedUserFriendlyMessage())
        """
    case .leaf:
      return "Leaf"
    case .leafUnderlying(let underlying):
      return
        """
        Leaf
          \(ErrorKit.userFriendlyMessage(for: underlying))
        """
    case .caught(let error):
      return userFriendlyCaughtMessage(error)
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
            GenericError(userFriendlyMessage: "Generic edge case")
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
                  underlying: GenericError(userFriendlyMessage: "Generic edge case")
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
                  underlying: GenericError(userFriendlyMessage: "Generic edge case")
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
                      Generic edge case
              Two: Failure
                Failure
                  Leaf
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
      networkError: NetworkError.generic(userFriendlyMessage: "Failed to fetch")
    )
    #expect(
      error.userFriendlyMessage == """
        Failed to fetch url: https://example.com/search ->
          Failed to fetch
        """
    )
  }
}
