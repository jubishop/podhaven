// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import ReadableErrorMacro
import Semaphore
import Testing

@testable import PodHaven

@ReadableError
enum FakeError: ReadableError, CatchingError {
  case failure(underlying: Error)
  case leaf
  case leafUnderlying(underlying: Error)
  case complexCaught(String, Error)
  case simple(String)
  case caught(Error)

  var message: String {
    switch self {
    case .failure:
      return
        """
        Failure
        """
    case .leaf:
      return
        """
        Leaf
        Line Two
          Indented Line
        """
    case .leafUnderlying:
      return
        """
        Leaf
        Wrapping:
        """
    case .complexCaught(let message, _):
      return
        """
        Complex: \(message)
        """
    case .simple(let message):
      return message
    case .caught: return ""
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

    #expect(ErrorKit.coreMessage(for: error) == "Failure")

    #expect(
      ErrorKit.message(for: error) == """
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

    #expect(
      ErrorKit.loggableMessage(for: error) == """
        [FakeError.failure]
        \(ErrorKit.message(for: error))
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

    #expect(ErrorKit.coreMessage(for: error) == "Failure")

    #expect(
      ErrorKit.message(for: error) == """
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

    #expect(
      ErrorKit.loggableMessage(for: error) == """
        [FakeError.failure]
        \(ErrorKit.message(for: error))
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

    #expect(ErrorKit.coreMessage(for: error) == "Failure")

    #expect(
      ErrorKit.message(for: error) == """
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

    #expect(
      ErrorKit.loggableMessage(for: error) == """
        [FakeError.failure]
        \(ErrorKit.message(for: error))
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
    let unsavedPodcast = try Create.unsavedPodcast()
    let unsavedEpisode = try Create.unsavedEpisode(media: MediaURL(url), title: episodeTitle)
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

    #expect(ErrorKit.coreMessage(for: error) == "Failure")

    #expect(
      ErrorKit.message(for: error) == """
        Failure
        FakeError.caught ->
          PlaybackError.mediaNotPlayable ->
            MediaGUID Not Playable
              PodcastEpisode: \(podcastEpisode.toString)
              MediaGUID: \(podcastEpisode.mediaGUID)
        """
    )

    #expect(
      ErrorKit.loggableMessage(for: error) == """
        [FakeError.failure]
        \(ErrorKit.message(for: error))
        """
    )
  }

  @Test("search error fetch failure formatting")
  func testSearchErrorFetchFailureFormatting() async throws {
    let error = SearchError.fetchFailure(
      request: URLRequest(url: URL(string: "https://example.com/search")!),
      caught: FakeError.simple("Failed to fetch")
    )

    #expect(ErrorKit.coreMessage(for: error) == "Failed to fetch url: https://example.com/search")

    #expect(
      ErrorKit.message(for: error) == """
        Failed to fetch url: https://example.com/search
        FakeError.simple ->
          Failed to fetch
        """
    )

    #expect(
      ErrorKit.loggableMessage(for: error) == """
        [SearchError.fetchFailure]
        \(ErrorKit.message(for: error))
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
      #expect(
        ErrorKit.coreMessage(for: error) == "[NSURLErrorDomain: -1001] The request timed out."
      )
      #expect(ErrorKit.message(for: error) == "[NSURLErrorDomain: -1001] The request timed out.")
      #expect(
        ErrorKit.loggableMessage(for: error) == """
          [NSURLError.Error]
          [NSURLErrorDomain: -1001] The request timed out.
          """
      )
      guard let urlError = error as? URLError, urlError.code == .timedOut
      else { return false }
      return true
    }

    let cancellationSemaphor = AsyncSemaphore(value: 0)
    let task = Task {
      async let expect = await #expect {
        _ = try await URLSession.shared.data(
          for: URLRequest(url: URL(string: "https://artisanalsoftware.com")!)
        )
      } throws: { error in
        #expect(ErrorKit.coreMessage(for: error) == "[NSURLErrorDomain: -999] cancelled")
        #expect(ErrorKit.message(for: error) == "[NSURLErrorDomain: -999] cancelled")
        #expect(
          ErrorKit.loggableMessage(for: error) == """
            [NSURLError.Error]
            [NSURLErrorDomain: -999] cancelled
            """
        )
        guard let urlError = error as? URLError, urlError.code == .cancelled
        else { return false }
        return true
      }
      cancellationSemaphor.signal()
      return await expect
    }
    await cancellationSemaphor.wait()
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

    #expect(ErrorKit.coreMessage(for: error) == "Failure")

    let baseError = ErrorKit.baseError(for: error)
    #expect(ErrorKit.message(for: baseError) == "At bottom")
    #expect(
      ErrorKit.loggableMessage(for: baseError) == """
        [FakeError.simple]
        At bottom
        """
    )
  }

  @Test("coreMessage uses baseError if top level is empty")
  func testCoreMessageUsesBaseErrorIfTopLevelIsEmpty() async throws {
    let error = FakeError.caught(
      FakeError.complexCaught(
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

    #expect(ErrorKit.coreMessage(for: error) == "At bottom")
  }
}
