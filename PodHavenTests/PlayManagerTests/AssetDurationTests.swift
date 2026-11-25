// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of asset duration tests", .container)
@MainActor struct AssetDurationTests {
  enum UnknownDuration: CaseIterable {
    case indefinite, invalid, positiveInfinity, zero

    var time: CMTime {
      switch self {
      case .indefinite: .indefinite
      case .invalid: .invalid
      case .positiveInfinity: .positiveInfinity
      case .zero: .zero
      }
    }
  }

  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.fakeEpisodeAssetLoader) private var episodeAssetLoader
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.stateManager) private var stateManager

  private var avPlayer: FakeAVPlayer {
    Container.shared.avPlayer() as! FakeAVPlayer
  }

  init() async throws {
    stateManager.start()
    cacheManager.start()
    PlayHelpers.setupCommandHandling()
  }

  @Test(
    "loading an asset without a known duration keeps the stored duration",
    arguments: UnknownDuration.allCases
  )
  func loadingKeepsStoredDuration(assetDuration: UnknownDuration) async throws {
    await playManager.start()
    let storedDuration = CMTime.seconds(1800)
    let podcastEpisode = try await Create.podcastEpisode(
      Create.unsavedEpisode(duration: storedDuration)
    )
    await episodeAssetLoader.respond(
      to: podcastEpisode.episode.mediaURL,
      data: (true, assetDuration.time)
    )

    let onDeck = try await PlayHelpers.load(podcastEpisode)
    #expect(onDeck.duration == storedDuration)

    let episode: Episode? = try await repo.episode(podcastEpisode.id)
    #expect(episode?.duration == storedDuration)
  }

  @Test("playing an indefinite asset with an implausibly long stored duration records no coverage")
  func implausibleStoredDurationRecordsNoCoverage() async throws {
    await playManager.start()
    let storedDuration = CMTime.seconds(100_000_000_000)
    let podcastEpisode = try await Create.podcastEpisode(
      Create.unsavedEpisode(duration: storedDuration)
    )
    await episodeAssetLoader.respond(
      to: podcastEpisode.episode.mediaURL,
      data: (true, .indefinite)
    )

    try await PlayHelpers.load(podcastEpisode)
    try await PlayHelpers.play()
    avPlayer.advanceTime(to: .seconds(6))
    try await PlayHelpers.waitForEpisode(
      podcastEpisode.id,
      attribute: \.currentTime,
      toBe: .seconds(6)
    )

    let (duration, coverage) = try await repo.db.read { db -> (CMTime?, Data?) in
      let row = try #require(
        try Row.fetchOne(
          db,
          Episode.withID(podcastEpisode.id)
            .select(Episode.Columns.duration, Episode.Columns.playbackCoverage)
        )
      )
      return (row[Episode.Columns.duration], row[Episode.Columns.playbackCoverage])
    }
    #expect(duration == storedDuration)
    #expect(coverage == nil)
  }

  @Test("caching an asset with an indefinite duration keeps the stored duration")
  func cachingKeepsStoredDuration() async throws {
    let storedDuration = CMTime.seconds(1800)
    await episodeAssetLoader.setDefaultHandler { _ in (true, .indefinite) }
    let podcastEpisode = try await Create.podcastEpisode(
      Create.unsavedEpisode(duration: storedDuration)
    )
    let taskID = try await CacheHelpers.unshiftToQueue(podcastEpisode.id)

    let fileURL = try await CacheHelpers.simulateBackgroundFinish(taskID)
    try await CacheHelpers.waitForFileRemoved(fileURL)
    let cachedURL = try await CacheHelpers.waitForCached(podcastEpisode.id)
    try await CacheHelpers.waitForCachedFile(cachedURL)

    let episode: Episode? = try await repo.episode(podcastEpisode.id)
    #expect(episode?.duration == storedDuration)
  }
}
