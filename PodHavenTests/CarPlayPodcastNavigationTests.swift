// Copyright Justin Bishop, 2026

import AVFoundation
import CarPlay
import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@MainActor
struct CarPlayPodcastScene {
  let coordinator = Container.shared.carPlayCoordinator()
  let controller = FakeCarPlayInterfaceController()
  let root: CPTabBarTemplate
  let podcasts: CPListTemplate

  init() throws {
    coordinator.connect(controller)
    controller.completions[0](true, nil)
    root = try #require(controller.roots.first as? CPTabBarTemplate)
    podcasts = try #require(root.templates.last as? CPListTemplate)
    root.selectTemplate(at: 2)
    root.delegate?.tabBarTemplate(root, didSelect: podcasts)
  }

  func stop() { coordinator.disconnect(controller) }

  static func rows(_ template: CPListTemplate) -> [CPListItem] {
    template.sections.flatMap(\.items).compactMap { $0 as? CPListItem }
  }

  @discardableResult
  static func tap(_ title: String, in template: CPListTemplate) throws -> CPListItem {
    let row = try #require(rows(template).first { $0.text == title })
    let handler = try #require(row.handler)
    handler(row) {}
    return row
  }

  func openAll() async throws -> CPListTemplate {
    try await Wait.until(
      { @MainActor in Self.rows(podcasts).contains { $0.text == "All Podcasts" } },
      { "Saved subscriptions must load" }
    )
    try Self.tap("All Podcasts", in: podcasts)
    return try #require(controller.topTemplate as? CPListTemplate)
  }

  func open(_ title: String) async throws -> CPListTemplate {
    let all = try await openAll()
    try Self.tap(title, in: all)
    let detail = try #require(controller.topTemplate as? CPListTemplate)
    try await Wait.until(
      { @MainActor in Self.rows(detail).contains { $0.text == "All Episodes" } },
      { "Saved episode destination must load" }
    )
    return detail
  }
}

@Suite("of CarPlay podcast navigation tests", .container)
@MainActor struct CarPlayPodcastNavigationTests {
  @Test("episode filters preserve ties, listening state, resume position, and navigation depth")
  func filtersAndResume() async throws {
    let date = Date(timeIntervalSince1970: 200)
    let series = try await Container.shared.repo()
      .insertSeries(
        UnsavedPodcastSeries(
          unsavedPodcast: try Create.unsavedPodcast(title: "Saved show", subscriptionDate: Date()),
          unsavedEpisodes: [
            try Create.unsavedEpisode(
              title: "Resuming",
              pubDate: date,
              duration: .seconds(120),
              currentTime: .seconds(30)
            ),
            try Create.unsavedEpisode(title: "Untouched", pubDate: date),
            try Create.unsavedEpisode(
              title: "Finished",
              pubDate: date.addingTimeInterval(1),
              finishDate: Date()
            ),
          ]
        )
      )
    let resuming = try #require(series.episodes.first { $0.title == "Resuming" })
    let untouched = try #require(series.episodes.first { $0.title == "Untouched" })
    let finished = try #require(series.episodes.first { $0.title == "Finished" })
    await Container.shared.fakeEpisodeAssetLoader()
      .respond(to: resuming.mediaURL, data: (true, .seconds(120)))
    await Container.shared.appLauncher().prepareForPlayback()
    try await Container.shared.playManager()
      .load(PodcastEpisode(podcast: series.podcast, episode: resuming))
    let scene = try CarPlayPodcastScene()
    defer { scene.stop() }
    let detail = try await scene.open("Saved show")
    let original = try #require(CarPlayPodcastScene.rows(detail).first { $0.text == "Resuming" })
    #expect(original.detailText?.contains("In progress") == true)
    #expect(original.detailText?.contains("New") == false)
    #expect(original.playbackProgress == 0.25)
    #expect(
      CarPlayPodcastScene.rows(detail).compactMap { $0.userInfo as? Episode.ID }
        == [resuming.id, untouched.id].sorted()
    )
    #expect(!CarPlayPodcastScene.rows(detail).contains { $0.text == "Finished" })
    for _ in 0..<5 {
      try CarPlayPodcastScene.tap("All Episodes", in: detail)
      #expect(
        CarPlayPodcastScene.rows(detail).compactMap { $0.userInfo as? Episode.ID } == [finished.id]
          + [resuming.id, untouched.id].sorted()
      )
      #expect(
        CarPlayPodcastScene.rows(detail).first { $0.text == "Finished" }?.detailText?
          .contains("Finished") == true
      )
      #expect(CarPlayPodcastScene.rows(detail).first { $0.text == "Resuming" } === original)
      try CarPlayPodcastScene.tap("Unfinished", in: detail)
    }
    #expect(scene.controller.templates.count == 3)
    try CarPlayPodcastScene.tap("Resuming", in: detail)
    try await Wait.until(
      { @MainActor in scene.controller.topTemplate === CPNowPlayingTemplate.shared },
      { "Shared selection must open Now Playing" }
    )
    #expect(scene.controller.templates.count == 4)
    #expect(Container.shared.sharedState().onDeck?.currentTime == .seconds(30))
    #expect(!Container.shared.sharedState().playbackStatus.playing)
    scene.controller.goBack()
    #expect(scene.controller.topTemplate === detail)
    #expect(CarPlayPodcastScene.rows(detail).first { $0.text == "Resuming" } === original)
  }

  @Test("all shows and episodes remain reachable within item budgets without growing the stack")
  func pagingAndEmptyShows() async throws {
    Container.shared.carPlayListLimits.context(.test) {
      { CarPlayListLimits(items: 4, sections: 1) }
    }
    let repo = Container.shared.repo()
    for index in 0..<9 {
      _ = try await Create.podcast(title: "Show \(index)", subscriptionDate: Date())
    }
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(title: "Show 10", subscriptionDate: Date()),
        unsavedEpisodes: try (0..<7)
          .map {
            try Create.unsavedEpisode(
              title: "Episode \($0)",
              pubDate: Date(timeIntervalSince1970: Double($0))
            )
          }
      )
    )
    let scene = try CarPlayPodcastScene()
    defer { scene.stop() }
    let all = try await scene.openAll()
    var names: [String] = []
    for _ in 0..<5 {
      let rows = CarPlayPodcastScene.rows(all)
      #expect(rows.count <= 4)
      #expect(all.sections.count == 1)
      names += rows.filter { $0.userInfo is Podcast.ID }.compactMap(\.text)
      if rows.contains(where: { $0.text == "Next page" }) {
        try CarPlayPodcastScene.tap("Next page", in: all)
      }
    }
    #expect(names == (0..<9).map { "Show \($0)" } + ["Show 10"])
    #expect(scene.controller.templates.count == 2)
    let retained = try #require(CarPlayPodcastScene.rows(all).first { $0.text == "Show 10" })
    _ = try await Create.podcast(title: "Show 11", subscriptionDate: Date())
    try await Wait.until(
      { @MainActor in CarPlayPodcastScene.rows(all).contains { $0.text == "Next page" } },
      { "New subscription must add a page without resetting the selected page" }
    )
    #expect(CarPlayPodcastScene.rows(all).first { $0.text == "Show 10" } === retained)
    try CarPlayPodcastScene.tap("Show 10", in: all)
    let detail = try #require(scene.controller.topTemplate as? CPListTemplate)
    try await Wait.until(
      { @MainActor in CarPlayPodcastScene.rows(detail).contains { $0.text == "Episode 6" } },
      { "Newest saved episodes must load" }
    )
    var ids: [Episode.ID] = []
    for _ in 0..<7 {
      #expect(detail.itemCount <= 4)
      ids += CarPlayPodcastScene.rows(detail).compactMap { $0.userInfo as? Episode.ID }
      if CarPlayPodcastScene.rows(detail).contains(where: { $0.text == "Next page" }) {
        try CarPlayPodcastScene.tap("Next page", in: detail)
      }
    }
    #expect(Set(ids) == Set(series.episodes.map(\.id)))
    #expect(ids.count == 7)
    #expect(scene.controller.templates.count == 3)
    scene.controller.goBack()
    #expect(scene.controller.topTemplate === all)
    #expect(CarPlayPodcastScene.rows(all).contains { $0.text == "Show 10" })
    for _ in 0..<4 { try CarPlayPodcastScene.tap("Previous page", in: all) }
    try CarPlayPodcastScene.tap("Show 0", in: all)
    let empty = try #require(scene.controller.topTemplate as? CPListTemplate)
    try await Wait.until(
      { @MainActor in CarPlayPodcastScene.rows(empty).contains { $0.text == "No saved episodes" } },
      { "Empty saved show must not start feed discovery" }
    )
    #expect(
      CarPlayPodcastScene.rows(empty).first { $0.text == "No saved episodes" }?.isEnabled == false
    )
  }

  @Test(
    "subscription, saved episode, completion, and progress updates retain unaffected row identity"
  )
  func liveUpdates() async throws {
    let repo = Container.shared.repo()
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(title: "Live show", subscriptionDate: Date()),
        unsavedEpisodes: [
          try Create.unsavedEpisode(title: "Keep", duration: .seconds(100)),
          try Create.unsavedEpisode(title: "Finish"),
        ]
      )
    )
    let keep = try #require(series.episodes.first { $0.title == "Keep" })
    let finish = try #require(series.episodes.first { $0.title == "Finish" })
    let scene = try CarPlayPodcastScene()
    defer { scene.stop() }
    let detail = try await scene.open("Live show")
    let row = try #require(CarPlayPodcastScene.rows(detail).first { $0.text == "Keep" })
    try await repo.markFinished(finish.id)
    try await repo.updateCurrentTime(keep.id, currentTime: .seconds(25))
    try await repo.updateCachedFilename(keep.id, cachedFilename: "saved.mp3")
    try await Wait.until(
      { @MainActor in
        row.playbackProgress == 0.25 && row.detailText?.contains("Downloaded") == true
          && !CarPlayPodcastScene.rows(detail).contains { $0.text == "Finish" }
      },
      { "Finished membership, playback progress, and download state must update" }
    )
    #expect(CarPlayPodcastScene.rows(detail).first { $0.text == "Keep" } === row)
    _ = try await repo.upsertPodcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: series.podcast.unsaved,
        unsavedEpisode: try Create.unsavedEpisode(title: "Added", pubDate: Date.distantFuture)
      )
    )
    try await Wait.until(
      { @MainActor in CarPlayPodcastScene.rows(detail).contains { $0.text == "Added" } },
      { "New saved episodes must appear" }
    )
    #expect(
      CarPlayPodcastScene.rows(detail).first { $0.text == "Added" }?.detailText?
        .contains("Not started") == true
    )
    try await repo.markUnsubscribed(series.id)
    try await Wait.until(
      { @MainActor in scene.podcasts.itemCount == 0 },
      { "Unsubscription must remove subscribed roots" }
    )
    #expect(scene.controller.topTemplate === detail)
    #expect(CarPlayPodcastScene.rows(detail).contains { $0.text == "Keep" })
    try await repo.markSubscribed(series.id)
    try await Wait.until(
      { @MainActor in CarPlayPodcastScene.rows(scene.podcasts).contains { $0.text == "Live show" }
      },
      { "Subscription changes must restore roots" }
    )
    #expect(scene.controller.roots.count == 1)
  }

  @Test(
    "Now Playing resolves the actual current podcast and invalidates deleted destinations safely"
  )
  func currentShortcutAndDeletion() async throws {
    let repo = Container.shared.repo()
    let first = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(title: "First", subscriptionDate: Date()),
        unsavedEpisodes: [try Create.unsavedEpisode(title: "First episode")]
      )
    )
    let second = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(title: "Second"),
        unsavedEpisodes: [try Create.unsavedEpisode(title: "Second episode")]
      )
    )
    let secondEpisode = PodcastEpisode(podcast: second.podcast, episode: second.episodes[0])
    await Container.shared.appLauncher().prepareForPlayback()
    try await Container.shared.playManager()
      .load(PodcastEpisode(podcast: first.podcast, episode: first.episodes[0]))
    let scene = try CarPlayPodcastScene()
    defer { scene.stop() }
    let detail = try await scene.open("First")
    let oldRow = try #require(CarPlayPodcastScene.rows(detail).first { $0.text == "First episode" })
    try await Container.shared.playManager().load(secondEpisode)
    scene.controller.pushTemplate(CPNowPlayingTemplate.shared, animated: false, completion: nil)
    try await repo.deletePodcast(first.id)
    try await Wait.until(
      { @MainActor in detail.emptyViewTitleVariants == ["Podcast unavailable"] },
      { "Deleted detail must invalidate its episode handlers" }
    )
    #expect(oldRow.handler == nil)
    #expect(scene.controller.topTemplate === CPNowPlayingTemplate.shared)
    #expect(Container.shared.sharedState().currentEpisodeID == secondEpisode.id)
    scene.coordinator.nowPlayingTemplateAlbumArtistButtonTapped(CPNowPlayingTemplate.shared)
    let shortcut = try await Wait.forValue { @MainActor in
      let top = scene.controller.topTemplate as? CPListTemplate
      return top?.sections.flatMap(\.items).contains { $0.text == "Second episode" } == true
        ? top : nil
    }
    #expect(shortcut !== detail)
    #expect(scene.controller.templates.count == 2)
    #expect(try await repo.podcast(second.id)?.subscriptionDate == nil)
    #expect(Container.shared.sharedState().currentEpisodeID == secondEpisode.id)
    try await repo.deletePodcast(second.id)
    try await Wait.until(
      { @MainActor in !Container.shared.carPlayNowPlaying().isAlbumArtistButtonEnabled },
      { "Deleted current record must disable the shortcut" }
    )
  }
}
