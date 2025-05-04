// Copyright Justin Bishop, 2025

import AVFoundation
import ErrorKit
import Factory
import Foundation
import Testing

@testable import PodHaven

enum FakeError: KittedError {
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
        One: \(one.nestedUserFriendlyMessage)
        Two: \(two.nestedUserFriendlyMessage)
        """
    case .failure(let underlying):
      return
        """
        Failure
        \(underlying.nestedUserFriendlyMessage)
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
      return userFriendlyCaughtMessage(caught: error)
    }
  }
}

@Suite("of KittedError tests")
struct KittedErrorTests {
  private let repo: Repo = .inMemory()

  @Test("messages with caught generic at end")
  func testMessagesCaughtGenericAtEnd() {
    let error = FakeError.failure(
      underlying: FakeError.failure(
        underlying: FakeError.failure(
          underlying: FakeError.caught(
            GenericError(userFriendlyMessage: "Generic edge case")
          )
        )
      )
    )

    let expected =
      """
      Failure
        Failure
          Failure
            FakeError
              └─ Generic edge case
      """

    #expect(error.userFriendlyMessage == expected)
  }

  @Test("messages with caught kitted at end")
  func testMessagesCaughtKittedAtEnd() {
    let error = FakeError.failure(
      underlying: FakeError.failure(
        underlying: FakeError.failure(
          underlying: FakeError.caught(
            FakeError.leaf
          )
        )
      )
    )

    let expected =
      """
      Failure
        Failure
          Failure
            FakeError
              └─ Leaf
      """

    #expect(error.userFriendlyMessage == expected)
  }

  @Test("messages with caught kitted in middle")
  func testFormattingNestedUserFriendlyMessagesKittedAtEnd() {
    let error = FakeError.failure(
      underlying: FakeError.failure(
        underlying: FakeError.failure(
          underlying: FakeError.caught(
            FakeError.failure(
              underlying: FakeError.failure(
                underlying: FakeError.leafUnderlying(
                  underlying: GenericError(userFriendlyMessage: "Generic edge case")
                )
              )
            )
          )
        )
      )
    )

    let expected =
      """
      Failure
        Failure
          Failure
            FakeError
              └─ Failure
                Failure
                  Leaf
                    Generic edge case
      """

    #expect(error.userFriendlyMessage == expected)
  }

  @Test("messages with double failure")
  func testFormattingDoubleFailure() {
    let error = FakeError.failure(
      underlying: FakeError.failure(
        underlying: FakeError.doubleFailure(
          one: FakeError.caught(
            FakeError.failure(
              underlying: FakeError.failure(
                underlying: FakeError.leafUnderlying(
                  underlying: GenericError(userFriendlyMessage: "Generic edge case")
                )
              )
            )
          ),
          two: FakeError.failure(
            underlying: FakeError.failure(
              underlying: FakeError.leaf
            )
          )
        )
      )
    )

    let expected =
      """
      Failure
        Failure
          Failure
            One: FakeError
              └─ Failure
                Failure
                  Leaf
                    Generic edge case
            Two: Failure
              Failure
                Leaf
      """

    #expect(error.userFriendlyMessage == expected)
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
    let error = PlaybackError.mediaNotPlayable(podcastEpisode)
    #expect(
      error.userFriendlyMessage == """
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
        Failed to fetch url: https://example.com/search
          └─ Failed to fetch
        """
    )
  }
}
