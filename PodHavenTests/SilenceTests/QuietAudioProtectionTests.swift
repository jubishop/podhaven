// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Foundation
import Semaphore
import Testing

@testable import PodHaven

@Suite("Quiet audio protection preferences and playback", .container)
@MainActor struct QuietAudioProtectionTests {
  @Test("all independent precedence combinations and persisted defaults")
  func preferences() async throws {
    let settings = Container.shared.userSettings()
    #expect(settings.quietAudioProtection == .high)
    #expect(PodcastSettings.defaults.quietAudioProtection == nil)
    settings.$quietAudioProtection.new(.medium)
    Container.shared.userSettings.reset(.scope)
    #expect(Container.shared.userSettings().quietAudioProtection == .medium)
    let choices: [QuietAudioProtection?] =
      [nil] + QuietAudioProtection.allCases.map { Optional($0) }
    for global in QuietAudioProtection.allCases {
      for podcast in choices {
        for temporary in choices {
          #expect(
            QuietAudioProtection.resolve(temporary: temporary, podcast: podcast, global: global)
              == (temporary ?? podcast ?? global)
          )
        }
      }
    }
    let episode = try await Create.podcastEpisode()
    var preferences = episode.podcast.settings
    for protection in choices {
      preferences.quietAudioProtection = protection
      preferences.silenceMode = .balanced
      try await Container.shared.repo().updatePodcastSettings(episode.podcast.id, preferences)
      let updated = try #require(try await Container.shared.repo().podcastEpisode(episode.id))
      #expect(updated.podcast.quietAudioProtection == protection)
      #expect(OnDeck(from: updated).quietAudioProtection == protection)
      #expect(updated.podcast.silenceMode == .balanced)
    }
  }

  @Test("selecting either player control leaves the other preference inherited")
  func independentInheritance() async throws {
    let episode = try await Create.podcastEpisode()
    let state = Container.shared.sharedState()
    state.$onDeck.new(OnDeck(from: episode))
    state.currentEpisodeID = episode.id
    let settings = Container.shared.userSettings()
    let viewModel = PlayBarViewModel()
    viewModel.selectSilenceMode(.balanced)
    settings.$quietAudioProtection.new(.low)
    #expect(viewModel.quietAudioProtection == .low)
    #expect(viewModel.silenceMode == .balanced)
    state.$silenceOverride.new(nil)
    viewModel.selectQuietAudioProtection(.medium)
    settings.$silenceMode.new(.aggressive)
    settings.$quietAudioProtection.new(.high)
    #expect(viewModel.silenceMode == .aggressive)
    #expect(viewModel.quietAudioProtection == .medium)
    #expect(settings.quietAudioProtection == .high)
    #expect(
      try await Container.shared.repo().podcastEpisode(episode.id)?.podcast.quietAudioProtection
        == nil
    )
    state.$quietAudioProtectionOverride.new(nil)
    var preferences = episode.podcast.settings
    preferences.quietAudioProtection = .low
    preferences.silenceMode = .gentle
    try await Container.shared.repo().updatePodcastSettings(episode.podcast.id, preferences)
    state.$onDeck.new(
      OnDeck(from: try #require(try await Container.shared.repo().podcastEpisode(episode.id)))
    )
    #expect(viewModel.quietAudioProtection == .low)
    #expect(viewModel.silenceMode == .gentle)
  }

  private func prepared() async throws -> (FakeAVPlayer, CachedAudioContent, SilenceMap) {
    Container.shared.stateManager().start()
    Container.shared.cacheManager().start()
    PlayHelpers.setupCommandHandling()
    let episode = try await Create.podcastEpisode(
      Create.unsavedEpisode(cachedFilename: "protection.mp3")
    )
    let url = try #require(episode.episode.cachedURL)
    try await (Container.shared.fileManager() as! FakeFileManager)
      .writeData(Data("audio".utf8), to: url.rawValue)
    let store = Container.shared.silenceStore()
    let content = try #require(try await store.content(for: url.lastPathComponent))
    let map = SilenceMap(
      duration: 30,
      high: [],
      medium: [.init(start: 2, end: 5)],
      low: [.init(start: 1, end: 10)]
    )
    try await store.publish(map, for: content)
    Container.shared.userSettings().$silenceMode.new(.gentle)
    try await Container.shared.playManager().play(episode)
    let player = Container.shared.avPlayer() as! FakeAVPlayer
    (player.current as! FakeAVPlayerItem).setStatus(.readyToPlay)
    try await PlayHelpers.waitForPeriodicTimeObserver()
    return (player, content, map)
  }

  @Test("changing protection reuses complete analysis immediately without enabling Off")
  func immediateSelection() async throws {
    let (player, content, map) = try await prepared()
    player.advanceTime(to: .seconds(2.5))
    try await PlayHelpers.waitFor(.seconds(2.5))
    #expect(player.preciseSeekRequests.isEmpty)
    let viewModel = PlayBarViewModel()
    viewModel.selectSilenceMode(.off)
    viewModel.selectQuietAudioProtection(.low)
    await Container.shared.podAVPlayer().updateSilencePlayback()
    #expect(player.preciseSeekRequests.isEmpty)
    viewModel.selectSilenceMode(.gentle)
    try await Wait.until { @MainActor in
      player.preciseSeekRequests.contains { abs($0.0.seconds - 9.7) < 0.001 }
    } _: {
      "Expected protection playback transition"
    }
    try await PlayHelpers.waitFor(.seconds(9.7))
    #expect(try await Container.shared.silenceStore().content(for: content.filename)?.map == map)
    await Container.shared.playManager().pause()
    await Container.shared.playManager().seek(to: .seconds(2.5))
    await Container.shared.playManager().setRate(2)
    viewModel.selectQuietAudioProtection(.medium)
    await Container.shared.playManager().play()
    let target = 5 - 0.3 / sqrt(2)
    try await Wait.until { @MainActor in
      abs(player.currentTime().seconds - target) < 0.001
    } _: {
      "Expected protection playback transition"
    }
    #expect(try await Container.shared.silenceStore().content(for: content.filename)?.map == map)
    #expect(Container.shared.userSettings().quietAudioProtection == .high)
  }

  @Test("changing protection cancels a pending seek from the old threshold")
  func stalePendingCut() async throws {
    let (player, _, _) = try await prepared()
    player.advanceTime(to: .seconds(2))
    try await PlayHelpers.waitFor(.seconds(2))
    let release = AsyncSemaphore(value: 0)
    player.seekHandler = { _ in
      await release.wait()
      return true
    }
    defer { release.signal() }
    let viewModel = PlayBarViewModel()
    viewModel.selectQuietAudioProtection(.low)
    try await Wait.until { @MainActor in
      player.preciseSeekRequests.count == 1
    } _: {
      "Expected protection playback transition"
    }
    viewModel.selectQuietAudioProtection(.high)
    await Container.shared.podAVPlayer().updateSilencePlayback()
    release.signal()
    try await Wait.until { @MainActor in
      player.completedSeekCount == 1
    } _: {
      "Expected protection playback transition"
    }
    #expect(player.currentTime() == .seconds(2))
    player.advanceTime(to: .seconds(3))
    try await PlayHelpers.waitFor(.seconds(3))
    #expect(player.preciseSeekRequests.count == 1)
  }
}
