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

  private static var audioSession: FakeAudioSession { Container.shared.fakeAudioSession() }
  private static var dataLoader: FakeDataLoader { Container.shared.fakeDataLoader() }
  private static var episodeAssetLoader: FakeEpisodeAssetLoader {
    Container.shared.fakeEpisodeAssetLoader()
  }
  private static var playManager: PlayManager { Container.shared.playManager() }
  private static var queue: any Queueing { Container.shared.queue() }
  private static var repo: any Databasing { Container.shared.repo() }
  private static var sharedState: SharedState { Container.shared.sharedState() }

  private static var avPlayer: FakeAVPlayer {
    Container.shared.avPlayer() as! FakeAVPlayer
  }
  private static var nowPlayingInfo: [String: Any?]? {
    Container.shared.mpNowPlayingInfoCenter().nowPlayingInfo
  }

  // MARK: - Action Helpers

  @discardableResult
  static func load(_ podcastEpisode: PodcastEpisode) async throws -> OnDeck {
    #expect(try await playManager.load(podcastEpisode))
    return try await Wait.forValue { @MainActor in sharedState.onDeck }
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
      { Container.shared.sharedState().playbackStatus == status },
      {
        """
        Status is: \(Container.shared.sharedState().playbackStatus), \
        Expected: \(status)
        """
      }
    )
  }

  static func waitFor(_ time: CMTime) async throws {
    try await Wait.until(
      { @MainActor in
        (sharedState.onDeck?.currentTime ?? .zero) == time && nowPlayingCurrentTime == time
      },
      { @MainActor in
        """
        sharedState.onDeck?.currentTime: \(sharedState.onDeck?.currentTime ?? .zero), \
        nowPlayingCurrentTime: \(nowPlayingCurrentTime), \
        Expected: \(time)
        """
      }
    )
  }

  static func waitForOnDeck(_ podcastEpisode: PodcastEpisode?) async throws {
    try await Wait.until(
      { @MainActor in sharedState.onDeck?.id == podcastEpisode?.id },
      { @MainActor in
        """
        OnDeck is: \(String(describing: sharedState.onDeck?.toString)), \
        Expected: \(String(describing: podcastEpisode?.toString))
        """
      }
    )
  }

  static func waitForOnDeckArtwork() async throws {
    try await Wait.until(
      { @MainActor in
        sharedState.onDeck?.artwork != nil && nowPlayingHasArtwork
      },
      { @MainActor in
        """
        sharedState.onDeck?.artwork: \(sharedState.onDeck?.artwork != nil), \
        nowPlayingHasArtwork: \(nowPlayingHasArtwork)
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

  static func waitForQueueCount(_ expected: Int) async throws {
    try await Wait.until(
      { @MainActor in sharedState.queueCount == expected },
      { @MainActor in
        "Expected queueCount to be \(expected), but got \(sharedState.queueCount)"
      }
    )
  }

  static func waitForCurrentItem<T: RawRepresentable & Sendable>(_ assetURL: T) async throws
  where T.RawValue == URL {
    try await Wait.until(
      { await currentAssetURL == assetURL.rawValue },
      {
        """
        Current url is: \(String(describing: await currentAssetURL?.absoluteString)), \
        Expected: \(String(describing: assetURL.rawValue.absoluteString))
        """
      }
    )
  }

  static func waitForNoCurrentItem() async throws {
    try await Wait.until(
      { await currentAssetURL == nil },
      { "Expected current asset url to be nil" }
    )
  }

  static func waitForPeriodicTimeObserver() async throws {
    try await Wait.until(
      { await hasPeriodicTimeObservation() },
      { "Expected periodic time observer to be set" }
    )
  }

  static func waitForLoadResponse<T: RawRepresentable & Sendable>(for assetURL: T, count: Int = 1)
    async throws where T.RawValue == URL
  {
    try await Wait.until(
      { await episodeAssetLoader.responseCount(for: assetURL) == count },
      {
        """
        responseCount for \(assetURL) is: \
        \(await episodeAssetLoader.responseCount(for: assetURL)), \
        expected: \(count)
        """
      }
    )
  }

  static func waitForAudioActive(_ active: Bool) async throws {
    try await Wait.until(
      { await audioSession.active == active },
      {
        "Expected active to be \(active), got \(await audioSession.active)"
      }
    )
  }

  static func waitForConfigureCallCount(callCount: Int) async throws {
    try await Wait.until(
      { await audioSession.configureCallCount == callCount },
      {
        """
        Expected callCount to be \(callCount), \
        but was \(await audioSession.configureCallCount)
        """
      }
    )
  }

  static func waitForEpisode<Value: Equatable & Sendable>(
    _ episodeID: Episode.ID,
    attribute keyPath: KeyPath<Episode, Value> & Sendable,
    toBe expectedValue: Value
  ) async throws {
    try await Wait.until(
      {
        guard let fetchedEpisode: Episode = try await repo.episode(episodeID)
        else { return false }

        return fetchedEpisode[keyPath: keyPath] == expectedValue
      },
      {
        let fetchedEpisode: Episode? = try await repo.episode(episodeID)
        let actualValue = fetchedEpisode.map { String(describing: $0[keyPath: keyPath]) } ?? "<nil>"
        return """
          Expected episode \(keyPath) to be \(expectedValue), \
          but got \(actualValue)
          """
      }
    )
  }

  static func waitForFinished(_ podcastEpisode: PodcastEpisode) async throws {
    try await Wait.until(
      {
        guard let fetchedEpisode: Episode = try await repo.episode(podcastEpisode.id)
        else { return false }

        return fetchedEpisode.finished
      },
      { "Expected \(podcastEpisode.toString) to become finished" }
    )
  }

  static func waitForNoNowPlayingInfo() async throws {
    try await Wait.until(
      { @MainActor in nowPlayingInfo == nil },
      { "Expected nowPlayingInfo to be nil" }
    )
  }

  static func waitForNowPlayingInfo(key: String, value: Any?) async throws {
    try await Wait.until(
      { @MainActor in
        guard let info = nowPlayingInfo else { return false }
        let actual = info[key] ?? nil
        return valuesEqual(actual, value)
      },
      {
        @MainActor in
        let actualDescription: String = {
          guard let info = nowPlayingInfo else {
            return "<no nowPlayingInfo>"
          }
          return String(describing: info[key] ?? nil)
        }()
        let expectedDescription = String(describing: value)
        return "Expected \(key) to be \(expectedDescription) but got \(actualDescription)"
      }
    )
  }

  // MARK: - Timing Helpers

  static func executeMidLoad<T: RawRepresentable & Sendable>(
    for taggedURL: T,
    asyncProperties: (Bool, CMTime) = (true, .seconds(Double(60))),
    _ block: @escaping @Sendable () async throws -> Void
  ) async throws where T.RawValue == URL {
    let loadSemaphoreBegun = AsyncSemaphore(value: 0)
    let finishLoadingSemaphore = AsyncSemaphore(value: 0)
    await episodeAssetLoader.respond(to: taggedURL) { _ in
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
    let uiImage = uiImage ?? FakeDataLoader.create(imageURL)
    let fetchSemaphoreBegun = AsyncSemaphore(value: 0)
    let finishFetchingSemaphore = AsyncSemaphore(value: 0)
    dataLoader.respond(to: imageURL) { _ in
      fetchSemaphoreBegun.signal()
      await finishFetchingSemaphore.wait()
      return uiImage.pngData()!
    }
    Task {
      await fetchSemaphoreBegun.wait()
      try await block()
      finishFetchingSemaphore.signal()
    }
  }

  static func executeMidSeek(
    finished: Bool = true,
    _ block: @escaping @Sendable () async throws -> Void
  ) async throws {
    let seekSemaphoreBegun = AsyncSemaphore(value: 0)
    let finishSeekingSemaphore = AsyncSemaphore(value: 0)
    avPlayer.seekHandler = { _ in
      seekSemaphoreBegun.signal()
      await finishSeekingSemaphore.wait()
      return finished
    }
    Task {
      await seekSemaphoreBegun.wait()
      try await block()
      finishSeekingSemaphore.signal()
    }
  }

  // MARK: - Comparison Helpers

  static var nowPlayingPlaybackRate: Double {
    nowPlayingInfo![MPNowPlayingInfoPropertyPlaybackRate] as! Double
  }

  static var nowPlayingCurrentTime: CMTime {
    guard let info = nowPlayingInfo,
      let elapsed = info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double
    else { return .invalid }
    return CMTime.seconds(elapsed)
  }

  static var nowPlayingHasArtwork: Bool {
    guard let info = nowPlayingInfo else { return false }
    return info[MPMediaItemPropertyArtwork] != nil
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
}
