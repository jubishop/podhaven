// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import IdentifiedCollections
import Intents
import Testing
import UIKit

@testable import PodHaven

@Suite("of Siri media playback", .container)
@MainActor struct SiriMediaPlaybackTests {
  private func seed(_ episodes: [UnsavedEpisode]) async throws -> [PodcastEpisode] {
    Container.shared.appDB().startSiriCatalog(Container.shared.siriCatalogFile())
    let series = try await Container.shared.repo()
      .insertSeries(
        UnsavedPodcastSeries(
          unsavedPodcast: try Create.unsavedPodcast(title: "A saved show"),
          unsavedEpisodes: episodes
        )
      )
    return series.episodes.map { PodcastEpisode(podcast: series.podcast, episode: $0) }
  }

  private func removeCatalog() {
    try? FileManager.default.removeItem(
      at: Container.shared.siriCatalogFile().url.deletingLastPathComponent()
    )
  }

  private func perform(_ intent: INPlayMediaIntent) async throws -> Int {
    let delegate: any UIApplicationDelegate = AppDelegate()
    let handler = try #require(
      delegate.application?(UIApplication.shared, handlerFor: intent)
        as? any INPlayMediaIntentHandling
    )
    return await withCheckedContinuation { continuation in
      handler.handle(intent: intent) { response in
        continuation.resume(returning: response.code.rawValue)
      }
    }
  }

  @Test("a named saved episode starts through shared cold playback without CarPlay")
  func coldPlayback() async throws {
    let episodes = try await seed([Create.unsavedEpisode(title: "A named episode")])
    defer { removeCatalog() }
    let result = try await perform(SiriTestIntent.named("A named episode", type: .podcastEpisode))
    #expect(result == INPlayMediaIntentResponseCode.success.rawValue)
    #expect(Container.shared.sharedState().currentEpisodeID == episodes[0].id)
    #expect(Container.shared.sharedState().playbackStatus.playing)
    #expect(await Container.shared.playManager().settledOnDeckID == episodes[0].id)
  }

  @Test("explicit play resumes the paused current item without another asset load")
  func currentResume() async throws {
    let episodes = try await seed([
      Create.unsavedEpisode(title: "A paused episode", currentTime: .seconds(24))
    ])
    defer { removeCatalog() }
    await Container.shared.appLauncher().prepareForPlayback()
    try await Container.shared.playManager().load(episodes[0])
    try await PlayHelpers.waitFor(.paused)
    let originalTime = Container.shared.sharedState().onDeck?.currentTime
    #expect(
      try await perform(SiriTestIntent.named("A paused episode"))
        == INPlayMediaIntentResponseCode.success.rawValue
    )
    #expect(
      await Container.shared.fakeEpisodeAssetLoader()
        .responseCount(for: episodes[0].episode.mediaURL) == 1
    )
    #expect(Container.shared.sharedState().onDeck?.currentTime == originalTime)
    #expect(Container.shared.sharedState().playbackStatus.playing)
  }

  @Test("a podcast prefers its current unfinished episode over a newer episode")
  func podcastResume() async throws {
    let episodes = try await seed([
      Create.unsavedEpisode(title: "Older", pubDate: Date(timeIntervalSince1970: 1)),
      Create.unsavedEpisode(title: "Newer", pubDate: Date(timeIntervalSince1970: 2)),
    ])
    defer { removeCatalog() }
    await Container.shared.appLauncher().prepareForPlayback()
    try await Container.shared.playManager().load(episodes[0])
    #expect(
      try await perform(SiriTestIntent.named("A saved show", type: .podcastShow))
        == INPlayMediaIntentResponseCode.success.rawValue
    )
    #expect(Container.shared.sharedState().currentEpisodeID == episodes[0].id)
  }

  @Test("a podcast selects newest unfinished media with stable ID ties")
  func podcastNewest() async throws {
    let date = Date(timeIntervalSince1970: 100)
    let episodes = try await seed([
      Create.unsavedEpisode(
        title: "Finished",
        pubDate: date.addingTimeInterval(100),
        finishDate: date
      ),
      Create.unsavedEpisode(title: "First tie", pubDate: date),
      Create.unsavedEpisode(title: "Second tie", pubDate: date),
    ])
    defer { removeCatalog() }
    #expect(
      try await perform(SiriTestIntent.named("A saved show", type: .podcastShow))
        == INPlayMediaIntentResponseCode.success.rawValue
    )
    #expect(Container.shared.sharedState().currentEpisodeID == episodes[1].id)
  }

  @Test("an exhausted podcast fails accurately, while a named finished episode can replay")
  func finished() async throws {
    let episodes = try await seed([Create.unsavedEpisode(title: "Finished", finishDate: Date())])
    defer { removeCatalog() }
    #expect(
      try await perform(SiriTestIntent.named("A saved show", type: .podcastShow))
        == INPlayMediaIntentResponseCode.failureNoUnplayedContent.rawValue
    )
    #expect(
      try await perform(SiriTestIntent.named("Finished", type: .podcastEpisode))
        == INPlayMediaIntentResponseCode.success.rawValue
    )
    #expect(Container.shared.sharedState().currentEpisodeID == episodes[0].id)
  }

  @Test("a newer Siri request supersedes a suspended lookup and completes both callbacks once")
  func overlappingRequests() async throws {
    let episodes = try await seed([
      Create.unsavedEpisode(title: "First"), Create.unsavedEpisode(title: "Second"),
    ])
    defer { removeCatalog() }
    await Container.shared.appLauncher().prepareForPlayback()
    let repo = Container.shared.repo() as! FakeRepo
    repo.pendingPodcastEpisodeFetchSuspend(true)
    let responses = ThreadSafe<[Int]>([])
    Container.shared.siriPlayback().handler
      .handle(intent: SiriTestIntent.named("First")) { response in
        responses { $0.append(response.code.rawValue) }
      }
    try await repo.waitForPodcastEpisodeFetchSuspended()
    #expect(
      try await perform(SiriTestIntent.named("Second"))
        == INPlayMediaIntentResponseCode.success.rawValue
    )
    await repo.resumeAllPodcastEpisodeFetchSuspensions()
    #expect(responses() == [INPlayMediaIntentResponseCode.failure.rawValue])
    #expect(Container.shared.sharedState().currentEpisodeID == episodes[1].id)
    #expect(
      await Container.shared.fakeEpisodeAssetLoader()
        .responseCount(for: episodes[0].episode.mediaURL) == 0
    )
  }

  @Test("remote pause cancels Siri while its catalog file is still pending")
  func cancelPendingCatalog() async throws {
    let episodes = try await seed([Create.unsavedEpisode(title: "Pending catalog")])
    defer { removeCatalog() }
    let original = Container.shared.siriCatalogFile()
    let opened = ThreadSafe(false)
    let release = AsyncStream<Void>.makeStream()
    defer { release.continuation.finish() }
    let file = SiriCatalogFile(
      url: original.url,
      openForReading: { url in
        opened(true)
        for await _ in release.stream { break }
        return try FileHandle(forReadingFrom: url)
      }
    )
    Container.shared.siriCatalogFile.context(.test) { file }.reset(.scope)
    let responses = ThreadSafe<[Int]>([])
    Container.shared.siriPlayback().handler
      .handle(intent: SiriTestIntent.named("Pending catalog")) { response in
        responses { $0.append(response.code.rawValue) }
      }
    try await Wait.until({ opened() }, { "Catalog file open did not start" })
    await Container.shared.playManager().pause()
    try await Wait.until({ responses().count == 1 }, { "Pending catalog was not canceled" })
    release.continuation.yield(())
    let journal = SiriResolutionJournal(
      url: original.url.deletingLastPathComponent()
        .appendingPathComponent("siri-app-resolutions.json"),
      sessionID: "test",
      version: "test",
      build: "test",
      commit: "test",
      process: "app"
    )
    try await Wait.until(
      { journal.read().last?.summary.phase == .finished },
      { "Canceled catalog operation did not finish" }
    )
    #expect(responses() == [INPlayMediaIntentResponseCode.failure.rawValue])
    #expect(
      await Container.shared.fakeEpisodeAssetLoader()
        .responseCount(for: episodes[0].episode.mediaURL) == 0
    )
  }

  @Test("remote pause cancels a pending Siri lookup")
  func remoteCancellation() async throws {
    let episodes = try await seed([Create.unsavedEpisode(title: "Pending")])
    defer { removeCatalog() }
    await Container.shared.appLauncher().prepareForPlayback()
    let repo = Container.shared.repo() as! FakeRepo
    repo.pendingPodcastEpisodeFetchSuspend(true)
    let responses = ThreadSafe<[Int]>([])
    Container.shared.siriPlayback().handler
      .handle(intent: SiriTestIntent.named("Pending")) { response in
        responses { $0.append(response.code.rawValue) }
      }
    try await repo.waitForPodcastEpisodeFetchSuspended()
    await Container.shared.playManager().pause()
    try await Wait.until({ responses().count == 1 }, { "Superseded callback did not finish" })
    await repo.resumeAllPodcastEpisodeFetchSuspensions()
    #expect(responses() == [INPlayMediaIntentResponseCode.failure.rawValue])
    #expect(
      await Container.shared.fakeEpisodeAssetLoader()
        .responseCount(for: episodes[0].episode.mediaURL) == 0
    )
  }

  @Test("a stalled lookup times out once and cannot play when its result arrives late")
  func timeout() async throws {
    let episodes = try await seed([Create.unsavedEpisode(title: "Slow")])
    defer { removeCatalog() }
    await Container.shared.appLauncher().prepareForPlayback()
    let repo = Container.shared.repo() as! FakeRepo
    repo.pendingPodcastEpisodeFetchSuspend(true)
    let responses = ThreadSafe<[Int]>([])
    Container.shared.siriPlayback().handler
      .handle(intent: SiriTestIntent.named("Slow")) { response in
        responses { $0.append(response.code.rawValue) }
      }
    try await repo.waitForPodcastEpisodeFetchSuspended()
    let sleeper = Container.shared.sleeper() as! FakeSleeper
    try await sleeper.waitForSleepRequests(for: .seconds(30))
    await sleeper.advanceTime(by: .seconds(30))
    try await Wait.until({ responses().count == 1 }, { "Deadline did not complete the callback" })
    await repo.resumeAllPodcastEpisodeFetchSuspensions()
    #expect(responses() == [INPlayMediaIntentResponseCode.failure.rawValue])
    #expect(
      await Container.shared.fakeEpisodeAssetLoader()
        .responseCount(for: episodes[0].episode.mediaURL) == 0
    )
  }

  @Test("unavailable media returns failure rather than scheduled success")
  func unavailableMedia() async throws {
    let episodes = try await seed([Create.unsavedEpisode(title: "Unavailable")])
    defer { removeCatalog() }
    await Container.shared.fakeEpisodeAssetLoader()
      .respond(to: episodes[0].episode.mediaURL, error: URLError(.cannotLoadFromNetwork))
    #expect(
      try await perform(SiriTestIntent.named("Unavailable"))
        == INPlayMediaIntentResponseCode.failure.rawValue
    )
    #expect(!Container.shared.sharedState().playbackStatus.playing)
  }

  @Test("deletion during a suspended lookup invalidates the result before playback")
  func staleDeletion() async throws {
    let episodes = try await seed([Create.unsavedEpisode(title: "Deleted while resolving")])
    defer { removeCatalog() }
    await Container.shared.appLauncher().prepareForPlayback()
    let repo = Container.shared.repo() as! FakeRepo
    repo.pendingPodcastEpisodeFetchSuspend(true)
    let responses = ThreadSafe<[Int]>([])
    Container.shared.siriPlayback().handler
      .handle(intent: SiriTestIntent.named("Deleted while resolving")) { response in
        responses { $0.append(response.code.rawValue) }
      }
    try await repo.waitForPodcastEpisodeFetchSuspended()
    try await repo.deletePodcast(episodes[0].podcast.id)
    await repo.resumeAllPodcastEpisodeFetchSuspensions()
    try await Wait.until({ !responses().isEmpty }, { "Stale lookup did not complete" })
    #expect(responses() == [INPlayMediaIntentResponseCode.failure.rawValue])
    #expect(
      await Container.shared.fakeEpisodeAssetLoader()
        .responseCount(for: episodes[0].episode.mediaURL) == 0
    )
  }

  @Test("the main app accepts Siri media background handoff")
  func backgroundHandoff() throws {
    let delegate: any UIApplicationDelegate = AppDelegate()
    let intent = INPlayMediaIntent(
      mediaItems: nil,
      mediaContainer: nil,
      playShuffled: nil,
      playbackRepeatMode: .unknown,
      resumePlayback: nil,
      playbackQueueLocation: .unknown,
      playbackSpeed: nil,
      mediaSearch: nil
    )
    let handler = delegate.application?(UIApplication.shared, handlerFor: intent)
    #expect(handler is any INPlayMediaIntentHandling, "Missing Siri media handler")
  }
}
