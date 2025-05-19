// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import ReadableErrorMacro
import Testing

@testable import PodHaven

@ReadableError
enum FakeError: ReadableError, CatchingError {
  case doubleFailure(one: Error, two: Error)
  case failure(underlying: Error)
  case leaf
  case leafUnderlying(underlying: Error)
  case complexCaught(String, Error)
  case simple(String)
  case caught(Error)

  var message: String {
    switch self {
    case .doubleFailure(let one, let two):
      return
        """
        Failure
        One: \(ErrorKit.nestedCaughtMessage(for: one))
        Two: \(ErrorKit.nestedCaughtMessage(for: two))
        Done
        """
    case .failure(let underlying):
      return
        """
        Failure
        \(ErrorKit.nestedCaughtMessage(for: underlying))
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
        \(ErrorKit.nestedCaughtMessage(for: underlying))
        """
    case .complexCaught(let message, let error):
      return
        """
        Complex: \(message)
        \(ErrorKit.nestedCaughtMessage(for: error))
        """
    case .simple(let message):
      return message
    case .caught(let error):
      return ErrorKit.nestedCaughtMessage(for: error)
    }
  }
}

@Suite("of error tests", .container)
class ErrorTests {
  @DynamicInjected(\.repo) private var repo

  @Test("messages with caught generic at end")
  func testMessagesCaughtGenericAtEnd() {
    let error = FakeError.failure(
      underlying: FakeError.failure(
        underlying: FakeError.failure(
          underlying: FakeError.caught(
            FakeError.simple("Generic edge case")
          )
        )
      )
    )

    #expect(
      ErrorKit.loggableMessage(for: error) == """
        [FakeError.failure]
        Failure
        FakeError.failure ->
          Failure
          FakeError.failure ->
            Failure
            FakeError.caught ->
              FakeError.simple ->
                Generic edge case
        """
    )
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

    #expect(
      ErrorKit.loggableMessage(for: error) == """
        [FakeError.failure]
        Failure
        FakeError.failure ->
          Failure
          FakeError.failure ->
            Failure
            FakeError.caught ->
              FakeError.leaf ->
                Leaf
                Line Two
                  Indented Line
        """
    )
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
                  underlying: FakeError.simple("Generic edge case")
                )
              )
            )
          )
        )
      )
    )

    #expect(
      ErrorKit.loggableMessage(for: error) == """
        [FakeError.failure]
        Failure
        FakeError.failure ->
          Failure
          FakeError.failure ->
            Failure
            FakeError.caught ->
              FakeError.failure ->
                Failure
                FakeError.failure ->
                  Failure
                  FakeError.leafUnderlying ->
                    Leaf
                    Wrapping:
                    FakeError.simple ->
                      Generic edge case
        """
    )
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
                  underlying: FakeError.simple(
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
          two: FakeError.failure(
            underlying: FakeError.failure(
              underlying: FakeError.leaf
            )
          )
        )
      )
    )

    #expect(
      ErrorKit.loggableMessage(for: error) == """
        [FakeError.failure]
        Failure
        FakeError.failure ->
          Failure
          FakeError.doubleFailure ->
            Failure
            One: FakeError.caught ->
              FakeError.failure ->
                Failure
                FakeError.failure ->
                  Failure
                  FakeError.leafUnderlying ->
                    Leaf
                    Wrapping:
                    FakeError.simple ->
                      Generic edge case
                      Heyo
                        Indented
            Two: FakeError.failure ->
              Failure
              FakeError.failure ->
                Failure
                FakeError.leaf ->
                  Leaf
                  Line Two
                    Indented Line
            Done
        """
    )
  }

  @Test("simple catching pass through")
  func testSimpleCatchingPassThrough() {
    #expect(throws: FakeError.simple("Hello")) {
      try FakeError.catch {
        throw FakeError.simple("Hello")
      }
    }
  }

  @Test("catching wraps in caught")
  func testCatchingWrapsInCaught() {
    enum CaughtError: Error {
      case hello
    }

    #expect(throws: FakeError.caught(CaughtError.hello)) {
      try FakeError.catch {
        throw CaughtError.hello
      }
    }
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
    let error = FakeError.failure(
      underlying: FakeError.caught(
        PlaybackError.mediaNotPlayable(podcastEpisode)
      )
    )
    #expect(
      ErrorKit.loggableMessage(for: error) == """
        [FakeError.failure]
        Failure
        FakeError.caught ->
          PlaybackError.mediaNotPlayable ->
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
      caught: FakeError.simple("Failed to fetch")
    )
    #expect(
      ErrorKit.loggableMessage(for: error) == """
        [SearchError.fetchFailure]
        Failed to fetch url: https://example.com/search ->
        FakeError.simple ->
          Failed to fetch
        """
    )
  }

  @Test("typeName() looks good for NSURLError errors")
  func testTypeNameLooksGoodForNSURLErrorErrors() async throws {
    await #expect {
      _ = try await URLSession.shared.data(
        for: URLRequest(url: URL(string: "https://127.0.0.1")!, timeoutInterval: 0.0001)
      )
    } throws: { error in
      #expect(ErrorKit.typeName(for: error) == "NSURLError.Error")
      #expect(ErrorKit.domain(for: error) == "NSURLErrorDomain")
      #expect(ErrorKit.code(for: error) == -1001)
      #expect(ErrorKit.message(for: error) == "[NSURLErrorDomain: -1001] The request timed out.")
      guard let urlError = error as? URLError, urlError.code == .timedOut
      else { return false }
      return true
    }

    let task = Task {
      await #expect {
        _ = try await URLSession.shared.data(
          for: URLRequest(url: URL(string: "https://example.com")!)
        )
      } throws: { error in
        #expect(ErrorKit.typeName(for: error) == "NSURLError.Error")
        #expect(ErrorKit.domain(for: error) == "NSURLErrorDomain")
        #expect(ErrorKit.code(for: error) == -999)
        #expect(ErrorKit.message(for: error) == "[NSURLErrorDomain: -999] cancelled")
        guard let urlError = error as? URLError, urlError.code == .cancelled
        else { return false }
        return true
      }
    }
    try await Task.sleep(nanoseconds: 100_000_000)
    task.cancel()
  }

  @Test("baseError recurses all the way down")
  func testBaseErrorRecursesAllTheWayDown() async throws {
    let error = FakeError.failure(
      underlying: FakeError.complexCaught(
        "hello world",
        FakeError.failure(
          underlying: FakeError.caught(
            FakeError.failure(
              underlying: FakeError.complexCaught(
                "keep going",
                FakeError.leafUnderlying(
                  underlying: FakeError.simple("At bottom")
                )
              )
            )
          )
        )
      )
    )

    let baseError = error.baseError
    #expect(ErrorKit.message(for: baseError) == "At bottom")
  }
}
