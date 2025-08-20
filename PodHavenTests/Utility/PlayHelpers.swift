// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import MediaPlayer
import Semaphore
import Testing

@testable import PodHaven

@MainActor
enum PlayHelpers {
  // MARK: - Dependency Access

  private static var fakeEpisodeAssetLoader: FakeEpisodeAssetLoader {
    Container.shared.fakeEpisodeAssetLoader()
  }
  private static var imageFetcher: any ImageFetchable { Container.shared.imageFetcher() }
  private static var playManager: PlayManager { Container.shared.playManager() }
  private static var playState: PlayState { Container.shared.playState() }
  private static var queue: any Queueing { Container.shared.queue() }
  private static var repo: any Databasing { Container.shared.repo() }

  private static var avPlayer: FakeAVPlayer {
    Container.shared.avPlayer() as! FakeAVPlayer
  }
  private static var commandCenter: FakeCommandCenter {
    Container.shared.commandCenter() as! FakeCommandCenter
  }
  private static var fakeImageFetcher: FakeImageFetcher { imageFetcher as! FakeImageFetcher }
  private static var nowPlayingInfo: [String: Any?]? {
    Container.shared.mpNowPlayingInfoCenter().nowPlayingInfo
  }

  // MARK: - Action Helpers

  @discardableResult
  static func load(_ podcastEpisode: PodcastEpisode) async throws -> OnDeck {
    #expect(try await playManager.load(podcastEpisode))
    return try await Wait.forValue { await playState.onDeck }
  }

  static func play() async throws {
    await playManager.play()
    try await waitFor(.playing)
  }

  static func pause() async throws {
    await playManager.pause()
    try await waitFor(.paused)
  }

  // MARK: - Wait Helpers

  static func waitFor(_ status: PlaybackStatus) async throws {
    try await Wait.until(
      { await playState.status == status },
      {
        """
        Status is: \(await playState.status), \
        Expected: \(status)
        """
      }
    )
  }

  static func waitFor(_ time: CMTime) async throws {
    try await Wait.until(
      { await playState.currentTime == time },
      {
        """
        Current time is: \(await playState.currentTime), \
        Expected: \(time)
        """
      }
    )
  }

  static func waitForOnDeck(_ podcastEpisode: PodcastEpisode?) async throws {
    try await Wait.until(
      { await playState.onDeck?.id == podcastEpisode?.id },
      {
        """
        OnDeck MediaURL is: \(String(describing: await playState.onDeck?.mediaURL.hash())), \
        Expected: \(String(describing: podcastEpisode?.episode.media.toString))
        """
      }
    )
  }

  static func waitForQueue(_ podcastEpisodes: [PodcastEpisode]) async throws {
    try await Wait.until(
      { try await queuedEpisodeIDs == podcastEpisodes.map(\.id) },
      {
        """
        Queue is: \(try await queuedEpisodeStrings), \
        Expected: \(await episodeStrings(podcastEpisodes))
        """
      }
    )
  }

  static func waitForCurrentItem(_ podcastEpisode: PodcastEpisode?) async throws {
    try await Wait.until(
      {
        await currentAssetURL == podcastEpisode?.episode.mediaURL
      },
      {
        """
        Current url is: \(await currentAssetURL?.absoluteString ?? "nil"), \
        Expected: \(podcastEpisode?.episode.mediaURL.absoluteString ?? "nil")
        """
      }
    )
  }

  static func waitForPeriodicTimeObserver() async throws {
    try await Wait.until(
      { await hasPeriodicTimeObservation() },
      { "Expected periodic time observer to be set" }
    )
  }

  static func waitForResponse(for podcastEpisode: PodcastEpisode, count: Int = 1) async throws {
    try await Wait.until(
      { await responseCount(for: podcastEpisode) == count },
      {
        """
        responseCount for \(podcastEpisode.episode.media.toString) is: \
        \(await responseCount(for: podcastEpisode)), \
        expected: \(count)
        """
      }
    )
  }

  static func waitForCompleted(_ podcastEpisode: PodcastEpisode) async throws {
    try await Wait.until(
      {
        guard let fetchedEpisode: Episode = try await repo.episode(podcastEpisode.id)
        else { return false }

        return fetchedEpisode.completed
      },
      { "Expected \(podcastEpisode.toString) to become completed" }
    )
  }

  static func waitForIgnoringSeek() async throws {
    try await Wait.until(
      { await playManager.ignoreSeekCommands },
      { "Expected playManager to ignore seek commands" }
    )
  }

  static func waitForNotIgnoringSeek() async throws {
    try await Wait.until(
      { await playManager.ignoreSeekCommands == false },
      { "Expected playManager to stop ignoring seek commands" }
    )
  }

  // MARK: - Timing Helpers

  static func executeMidLoad(
    for podcastEpisode: PodcastEpisode,
    asyncProperties: (Bool, CMTime) = (true, .seconds(Double(60))),
    _ block: @escaping @Sendable () async throws -> Void
  ) async throws {
    let loadSemaphoreBegun = AsyncSemaphore(value: 0)
    let finishLoadingSemaphore = AsyncSemaphore(value: 0)
    await fakeEpisodeAssetLoader.respond(to: podcastEpisode.episode) { _ in
      loadSemaphoreBegun.signal()
      await finishLoadingSemaphore.wait()
      return asyncProperties
    }
    Task {
      await loadSemaphoreBegun.wait()
      try await block()
      finishLoadingSemaphore.signal()
    }
  }

  static func executeMidImageFetch(
    for imageURL: URL,
    uiImage: UIImage? = nil,
    _ block: @escaping @Sendable () async throws -> Void
  ) async throws {
    let uiImage = uiImage ?? FakeImageFetcher.create(imageURL)
    let fetchSemaphoreBegun = AsyncSemaphore(value: 0)
    let finishFetchingSemaphore = AsyncSemaphore(value: 0)
    await fakeImageFetcher.respond(to: imageURL) { _ in
      fetchSemaphoreBegun.signal()
      await finishFetchingSemaphore.wait()
      return uiImage
    }
    Task {
      await fetchSemaphoreBegun.wait()
      try await block()
      finishFetchingSemaphore.signal()
    }
  }

  static func executeMidSeek(
    completed: Bool = true,
    _ block: @escaping @Sendable () async throws -> Void
  ) async throws {
    let seekSemaphoreBegun = AsyncSemaphore(value: 0)
    let finishSeekingSemaphore = AsyncSemaphore(value: 0)
    avPlayer.seekHandler = { _ in
      seekSemaphoreBegun.signal()
      await finishSeekingSemaphore.wait()
      return completed
    }
    Task {
      await seekSemaphoreBegun.wait()
      try await block()
      finishSeekingSemaphore.signal()
    }
  }

  // MARK: - Comparison Helpers

  static var nowPlayingPlaying: Bool {
    nowPlayingInfo![MPNowPlayingInfoPropertyPlaybackRate] as? Double == 1.0
  }

  static var nowPlayingCurrentTime: CMTime {
    CMTime.seconds(nowPlayingInfo![MPNowPlayingInfoPropertyElapsedPlaybackTime] as! Double)
  }

  static var nowPlayingProgress: Double {
    nowPlayingInfo![MPNowPlayingInfoPropertyPlaybackProgress] as! Double
  }

  static var currentAssetURL: URL? {
    guard let current = avPlayer.current as? FakeAVPlayerItem
    else { return nil }

    return current.url
  }

  static var queuedEpisodes: [PodcastEpisode] {
    get async throws {
      try await repo.db.read { db in
        try Episode
          .all()
          .queued()
          .order(\.queueOrder.asc)
          .including(required: Episode.podcast)
          .asRequest(of: PodcastEpisode.self)
          .fetchAll(db)
      }
    }
  }

  static var queuedEpisodeIDs: [Episode.ID] {
    get async throws {
      try await queuedEpisodes.map(\.id)
    }
  }

  static var queuedEpisodeStrings: [String] {
    get async throws {
      episodeStrings(try await queuedEpisodes)
    }
  }

  static func episodeStrings(_ podcastEpisodes: [PodcastEpisode]) -> [String] {
    podcastEpisodes.map(\.toString)
  }

  static func hasPeriodicTimeObservation() -> Bool {
    !(avPlayer.timeObservers.isEmpty)
  }

  static func responseCount(for podcastEpisode: PodcastEpisode) async -> Int {
    await fakeEpisodeAssetLoader.responseCount(for: podcastEpisode)
  }
}
