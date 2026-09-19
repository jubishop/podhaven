// Copyright Justin Bishop, 2026

import AVFoundation
import CarPlay
import FactoryKit
import FactoryTesting
import Foundation
import MediaPlayer
import Testing

@testable import PodHaven

@Suite("of CarPlay integrated MVP tests", .container)
@MainActor struct CarPlayIntegrationTests {
  @Test(
    "all browsers share cached or streamed playback with widgets and remote controls",
    arguments: [false, true]
  )
  func sharedSurfaces(cached: Bool) async throws {
    PlayHelpers.setupCommandHandling()
    try await CarPlaySmartListScene.clear()
    _ = try await CarPlaySmartListScene.insert("Saved episodes")
    let title = String(repeating: "Long episode — 日本語 العربية 🎧 ", count: 8)
    let series = try await Container.shared.repo()
      .insertSeries(
        UnsavedPodcastSeries(
          unsavedPodcast: try Create.unsavedPodcast(
            title: "Saved podcast",
            subscriptionDate: Date()
          ),
          unsavedEpisodes: [
            try Create.unsavedEpisode(
              title: title,
              duration: .seconds(120),
              cachedFilename: cached ? "carplay-integration.mp3" : nil
            ),
            try Create.unsavedEpisode(title: "Next episode", duration: .seconds(120)),
          ]
        )
      )
    let first = PodcastEpisode(
      podcast: series.podcast,
      episode: try #require(series.episodes.first { $0.title == title })
    )
    let next = PodcastEpisode(
      podcast: series.podcast,
      episode: try #require(series.episodes.first { $0.title == "Next episode" })
    )
    await Container.shared.fakeEpisodeAssetLoader().setDefaultHandler { _ in (true, .seconds(120)) }
    try await Container.shared.queue().append(first.id)
    try await Container.shared.queue().append(next.id)

    let scene = try CarPlaySmartListScene()
    defer { scene.stop() }
    let detail = try await scene.open("Saved episodes")
    let selected = try #require(
      CarPlaySmartListScene.rows(detail).first { $0.userInfo as? Episode.ID == first.id }
    )
    #expect(selected.text == title)
    #expect(selected.detailText?.contains("Saved podcast") == true)
    #expect(selected.isEnabled)
    #expect(await Container.shared.fakeAudioSession().activeCalls.isEmpty)
    #expect(Container.shared.sharedState().onDeck == nil)
    let completion = ThreadSafe(0)
    let handler = try #require(selected.handler)
    handler(selected) { completion { $0 += 1 } }
    try await Wait.until({ completion() == 1 }, { "Episode selection must complete" })
    try await PlayHelpers.waitFor(.playing)
    #expect(scene.controller.topTemplate === CPNowPlayingTemplate.shared)
    #expect(PlayHelpers.currentAssetURL?.isFileURL == cached)
    try await PlayHelpers.waitForNowPlayingInfo(key: MPMediaItemPropertyTitle, value: title)
    try await WidgetHelpers.waitForNowPlayingSnapshot {
      $0.nowPlaying?.episodeID == first.id.rawValue
    }
    try await WidgetHelpers.waitForQueueSnapshot { $0.queue.map(\.episodeID) == [next.id.rawValue] }

    let pause = try await PlayPauseIntent(playing: false).perform()
    withExtendedLifetime(pause) {}
    try await PlayHelpers.waitFor(.paused)
    let remote = Container.shared.mpRemoteCommandCenter() as! FakeMPRemoteCommandCenter
    #expect(remote.play.isEnabled)
    #expect(remote.changePlaybackPosition.isEnabled)
    remote.firePlay()
    try await PlayHelpers.waitFor(.playing)
    remote.fireChangePlaybackRate(1.5)
    try await PlayHelpers.waitForPlayRate(1.5)
    remote.fireSeek(to: 30)
    try await PlayHelpers.waitFor(.seconds(30))
    try await PlayHelpers.waitForNowPlayingInfo(
      key: MPNowPlayingInfoPropertyPlaybackRate,
      value: 1.5
    )

    scene.coordinator.nowPlayingTemplateUpNextButtonTapped(CPNowPlayingTemplate.shared)
    let upNext = try #require(scene.root.templates.first as? CPListTemplate)
    try await Wait.until(
      { @MainActor in CarPlaySmartListScene.rows(upNext).first?.playbackProgress == 0.25 },
      { "Up Next must show the shared seek position" }
    )
    #expect(CarPlaySmartListScene.rows(upNext).first?.isPlaying == true)
    #expect(scene.root.selectedTemplate === upNext)
    let podcasts = try #require(scene.root.templates.last as? CPListTemplate)
    scene.root.selectTemplate(at: 2)
    scene.root.delegate?.tabBarTemplate(scene.root, didSelect: podcasts)
    try await Wait.until(
      { @MainActor in CarPlaySmartListScene.rows(podcasts).contains { $0.text == "All Podcasts" } },
      { "Podcasts must remain available after Smart List playback" }
    )
    try CarPlaySmartListScene.tap("All Podcasts", in: podcasts)
    let all = try #require(scene.controller.topTemplate as? CPListTemplate)
    try CarPlaySmartListScene.tap("Saved podcast", in: all)
    let podcastDetail = try #require(scene.controller.topTemplate as? CPListTemplate)
    try await Wait.until(
      { @MainActor in CarPlaySmartListScene.rows(podcastDetail).contains { $0.text == title } },
      { "Podcast detail must resolve the same saved episode" }
    )
    try CarPlaySmartListScene.tap("All Episodes", in: podcastDetail)
    try CarPlaySmartListScene.tap(title, in: podcastDetail)
    try await Wait.until(
      { @MainActor in scene.controller.topTemplate === CPNowPlayingTemplate.shared },
      { "The current episode must reopen Now Playing" }
    )
    #expect(scene.controller.templates.count == 4)
    #expect(Container.shared.sharedState().onDeck?.currentTime == .seconds(30))
    #expect(Container.shared.sharedState().playRate == 1.5)
    scene.controller.goBack()
    #expect(scene.controller.topTemplate === podcastDetail)

    let widgetPlay = try await PlayEpisodeIntent(episodeID: next.id.rawValue).perform()
    withExtendedLifetime(widgetPlay) {}
    try await PlayHelpers.waitForOnDeck(next)
    try await PlayHelpers.waitFor(.playing)
    try await PlayHelpers.waitForNowPlayingInfo(key: MPMediaItemPropertyTitle, value: next.title)
    try await WidgetHelpers.waitForNowPlayingSnapshot {
      $0.nowPlaying?.episodeID == next.id.rawValue
    }
    try await WidgetHelpers.waitForQueueSnapshot {
      $0.queue.map(\.episodeID) == [first.id.rawValue]
    }
    try await Wait.until(
      { @MainActor in
        CarPlaySmartListScene.rows(podcastDetail).first { $0.text == next.title }?.isPlaying == true
      },
      { "CarPlay must follow a widget playback request" }
    )
    #expect(scene.controller.roots.count == 1)
    #expect(scene.controller.alerts.isEmpty)
  }

  @Test(
    "media-services reset recovers through CarPlay and shared Play without a phone alert action"
  )
  func mediaServicesRecovery() async throws {
    PlayHelpers.setupCommandHandling()
    let episode = try await Create.podcastEpisode(Create.unsavedEpisode(currentTime: .seconds(12)))
    await Container.shared.appLauncher().prepareForPlayback()
    try await Container.shared.playManager().play(episode)
    try await PlayHelpers.waitFor(.playing)
    let scene = try CarPlayPodcastScene()
    defer { scene.stop() }
    let initialPlayer = Container.shared.avPlayer() as! FakeAVPlayer
    Container.shared.notifier().continuation(for: AVAudioSession.mediaServicesWereResetNotification)
      .yield(Notification(name: AVAudioSession.mediaServicesWereResetNotification))
    try await Wait.until(
      { @MainActor in Container.shared.avPlayer() as! FakeAVPlayer !== initialPlayer },
      { "Media reset must replace the retired player" }
    )
    try await PlayHelpers.waitFor(.stopped)
    let upNext = try #require(scene.root.templates.first as? CPListTemplate)
    scene.root.selectTemplate(at: 0)
    scene.root.delegate?.tabBarTemplate(scene.root, didSelect: upNext)
    try await Wait.until(
      { @MainActor in CarPlayPodcastScene.rows(upNext).contains { $0.text == episode.title } },
      { "The preserved episode must stay reachable after reset" }
    )
    try CarPlayPodcastScene.tap(episode.title, in: upNext)
    try await Wait.until(
      { @MainActor in scene.controller.topTemplate === CPNowPlayingTemplate.shared },
      { "CarPlay must reach transport controls after reset" }
    )
    #expect(Container.shared.sharedState().playbackStatus == .stopped)
    let remote = Container.shared.mpRemoteCommandCenter() as! FakeMPRemoteCommandCenter
    #expect(remote.play.isEnabled)
    remote.firePlay()
    try await PlayHelpers.waitFor(.playing)
    try await PlayHelpers.waitFor(.seconds(12))
    #expect(scene.controller.alerts.isEmpty)
    #expect(Container.shared.sharedState().currentEpisodeID == episode.id)
    #expect(
      await Container.shared.fakeEpisodeAssetLoader().responseCount(for: episode.episode.mediaURL)
        == 2
    )
  }

  @Test(
    "interruption and repeated reconnect preserve one shared player and release scene observers"
  )
  func interruptionAndReconnect() async throws {
    PlayHelpers.setupCommandHandling()
    let episode = try await Create.podcastEpisode()
    await Container.shared.appLauncher().prepareForPlayback()
    try await Container.shared.playManager().play(episode)
    try await PlayHelpers.waitFor(.playing)
    let player = Container.shared.avPlayer() as! FakeAVPlayer
    let item = player.current
    let coordinator = Container.shared.carPlayCoordinator()
    let nowPlaying = Container.shared.carPlayNowPlaying() as! FakeCarPlayNowPlaying
    let interruptions = Container.shared.notifier()
      .continuation(for: AVAudioSession.interruptionNotification)
    for _ in 0..<3 {
      let controller = FakeCarPlayInterfaceController()
      coordinator.connect(controller)
      controller.completions[0](true, nil)
      #expect(nowPlaying.observers.count == 1)
      interruptions.yield(
        Notification(
          name: AVAudioSession.interruptionNotification,
          userInfo: [
            AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue
          ]
        )
      )
      try await PlayHelpers.waitFor(.paused)
      let calls = await Container.shared.fakeAudioSession().activeCalls
      coordinator.disconnect(controller)
      #expect(nowPlaying.observers.isEmpty)
      #expect(nowPlaying.buttons.isEmpty)
      #expect(controller.delegate == nil)
      #expect(player.current === item)
      #expect(await Container.shared.fakeAudioSession().activeCalls == calls)
      interruptions.yield(
        Notification(
          name: AVAudioSession.interruptionNotification,
          userInfo: [
            AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
            AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume
              .rawValue,
          ]
        )
      )
      try await PlayHelpers.waitFor(.playing)
      #expect(player.current === item)
      #expect(controller.pushed.isEmpty)
      #expect(controller.alerts.isEmpty)
    }
    #expect(
      await Container.shared.fakeEpisodeAssetLoader().responseCount(for: episode.episode.mediaURL)
        == 1
    )
  }
}
