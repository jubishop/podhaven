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

  private static var episodeAssetLoader: EpisodeAssetLoader {
    Container.shared.episodeAssetLoader()
  }
  private static var images: any ImageFetchable { Container.shared.images() }
  private static var playManager: PlayManager { Container.shared.playManager() }
  private static var playState: PlayState { Container.shared.playState() }
  private static var queue: Queue { Container.shared.queue() }
  private static var repo: Repo { Container.shared.repo() }

  private static var avQueuePlayer: FakeAVQueuePlayer {
    Container.shared.avQueuePlayer() as! FakeAVQueuePlayer
  }
  private static var commandCenter: FakeCommandCenter {
    Container.shared.commandCenter() as! FakeCommandCenter
  }
  private static var nowPlayingInfo: [String: Any?]? {
    Container.shared.mpNowPlayingInfoCenter().nowPlayingInfo
  }

  // MARK: - Action Helpers

  @discardableResult
  static func load(_ podcastEpisode: PodcastEpisode) async throws -> OnDeck {
    #expect(try await playManager.load(podcastEpisode))
    try await waitForObservations()
    return try await Wait.forValue { await playState.onDeck }
  }

  static func queueNext(_ podcastEpisode: PodcastEpisode) async throws {
    try await queue.unshift(podcastEpisode.id)
    try await Wait.until(
      { try await queue.nextEpisode?.id == podcastEpisode.id },
      {
        """
        Next episode ID: \(String(describing: try await queue.nextEpisode?.id)), \
        Expected: \(podcastEpisode.id)
        """
      }
    )
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

  static func waitFor(_ status: PlayState.Status) async throws {
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

  static func waitForOnDeck(_ podcastEpisode: PodcastEpisode) async throws {
    try await Wait.until(
      { await playState.onDeck?.media == podcastEpisode.episode.media },
      {
        """
        OnDeck MediaURL is: \(String(describing: await playState.onDeck?.media.toString)), \
        Expected: \(podcastEpisode.episode.media.toString)
        """
      }
    )
  }

  static func waitForQueue(_ podcastEpisodes: [PodcastEpisode]) async throws {
    try await Wait.until(
      { try await queuedEpisodeIDs == podcastEpisodes.map(\.id) },
      {
        """
        Quue is: \(try await queuedEpisodeStrings), \
        Expected: \(await episodeStrings(podcastEpisodes))
        """
      }
    )
  }

  static func waitForItemQueue(_ podcastEpisodes: [PodcastEpisode]) async throws {
    try await Wait.until(
      {
        let mediaURLs = await episodeMediaURLs(podcastEpisodes)
        return await itemQueueURLs == mediaURLs
      },
      {
        """
        Item queue is: \(await itemQueueURLs), \
        Expected: \(await episodeMediaURLs(podcastEpisodes))
        """
      }
    )
  }

  static func waitForPeriodicTimeObserver() async throws {
    try await Wait.until { await hasPeriodicTimeObservation() }
  }

  static func waitForNoPeriodicTimeObserver() async throws {
    try await Wait.until { !(await hasPeriodicTimeObservation()) }
  }

  static func waitForObservations() async throws {
    try await Wait.until { await hasObservations() }
  }

  static func waitForNoObservations() async throws {
    try await Wait.until { !(await hasObservations()) }
  }

  static func waitForResponse(for mediaURL: MediaURL, count: Int = 1) async throws {
    try await Wait.until(
      { await PlayHelpers.responseCount(for: mediaURL) == count },
      {
        """
        responseCount for \(mediaURL.toString) is: \
        \(await responseCount(for: mediaURL)), \
        expected: \(count)
        """
      }
    )
  }

  static func waitForCompleted(_ podcastEpisode: PodcastEpisode) async throws {
    try await Wait.until(
      {
        guard let fetchedPodcastEpisode = try await repo.episode(podcastEpisode.id)
        else { return false }

        return fetchedPodcastEpisode.episode.completed
      },
      { "Expected \(podcastEpisode.toString) to become completed" }
    )
  }

  // MARK: - Timing Helpers

  static func executeMidLoad(
    for mediaURL: MediaURL,
    asyncProperties: (Bool, CMTime) = (true, .inSeconds(30)),
    _ block: @escaping @Sendable () async throws -> Void
  ) async throws {
    let loadSemaphoreBegun = AsyncSemaphore(value: 0)
    let finishLoadingSemaphore = AsyncSemaphore(value: 0)
    episodeAssetLoader.respond(to: mediaURL) { _ in
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

  static func executeMidSeek(
    completed: Bool = true,
    _ block: @escaping @Sendable () async throws -> Void
  ) async throws {
    let seekSemaphoreBegun = AsyncSemaphore(value: 0)
    let finishSeekingSemaphore = AsyncSemaphore(value: 0)
    avQueuePlayer.seekHandler = { _ in
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
    CMTime.inSeconds(nowPlayingInfo![MPNowPlayingInfoPropertyElapsedPlaybackTime] as! Double)
  }

  static var nowPlayingProgress: Double {
    nowPlayingInfo![MPNowPlayingInfoPropertyPlaybackProgress] as! Double
  }

  static var itemQueueURLs: [MediaURL] {
    avQueuePlayer.queued.map(\.assetURL)
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

  static func episodeMediaURLs(_ podcastEpisodes: [PodcastEpisode]) -> [MediaURL] {
    podcastEpisodes.map(\.episode.media)
  }

  static func hasPeriodicTimeObservation() -> Bool {
    !(avQueuePlayer.timeObservers.isEmpty)
  }

  static func hasObservations() -> Bool {
    !(avQueuePlayer.itemObservations.isEmpty)
      && hasPeriodicTimeObservation()
      && !(avQueuePlayer.statusObservations.isEmpty)
  }

  static func responseCount(for mediaURL: MediaURL) -> Int {
    episodeAssetLoader.responseCounts[mediaURL, default: 0]
  }
}
