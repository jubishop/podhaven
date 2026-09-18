// Copyright Justin Bishop, 2026

import CarPlay
import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Semaphore
import Testing

@testable import PodHaven

@Suite("of CarPlay podcast recovery tests", .container)
@MainActor struct CarPlayPodcastRecoveryTests {
  @Test("a rejected podcast shortcut preserves the previous detail until navigation succeeds")
  func rejectedShortcutPreservesDetail() async throws {
    let series = try await Container.shared.repo()
      .insertSeries(
        UnsavedPodcastSeries(
          unsavedPodcast: try Create.unsavedPodcast(title: "Saved show", subscriptionDate: Date()),
          unsavedEpisodes: [try Create.unsavedEpisode(title: "Saved episode")]
        )
      )
    let episode = try #require(series.episodes.first)
    Container.shared.stateManager()
      .setOnDeck(
        PodcastEpisode(podcast: series.podcast, episode: episode)
      )
    let scene = try CarPlayPodcastScene()
    defer { scene.stop() }
    let detail = try await scene.open("Saved show")
    let row = try #require(CarPlayPodcastScene.rows(detail).first { $0.text == "Saved episode" })
    scene.controller.pushTemplate(CPNowPlayingTemplate.shared, animated: false, completion: nil)
    scene.controller.popResult = false
    scene.coordinator.nowPlayingTemplateAlbumArtistButtonTapped(CPNowPlayingTemplate.shared)
    try await Wait.until(
      { @MainActor in scene.controller.alerts.count == 1 },
      { "Rejected navigation must report its error" }
    )
    #expect(scene.controller.topTemplate === CPNowPlayingTemplate.shared)
    scene.controller.goBack()
    #expect(scene.controller.topTemplate === detail)
    #expect(CarPlayPodcastScene.rows(detail).first { $0.text == "Saved episode" } === row)
    #expect(row.handler != nil)
    try CarPlayPodcastScene.tap("All Episodes", in: detail)
    #expect(CarPlayPodcastScene.rows(detail).contains { $0.text == "Unfinished" })
    try await Container.shared.repo().markFinished(episode.id)
    try await Wait.until(
      { @MainActor in row.detailText?.contains("Finished") == true },
      { "The retained detail must still observe saved changes" }
    )
    scene.controller.pushTemplate(CPNowPlayingTemplate.shared, animated: false, completion: nil)
    scene.controller.popResult = true
    scene.coordinator.nowPlayingTemplateAlbumArtistButtonTapped(CPNowPlayingTemplate.shared)
    try await Wait.until(
      { @MainActor in
        guard let top = scene.controller.topTemplate as? CPListTemplate else { return false }
        return top !== detail
          && CarPlayPodcastScene.rows(top).contains { $0.text == "No unfinished episodes" }
      },
      { "A successful retry must open a fresh detail" }
    )
    #expect(row.handler == nil)
    #expect(scene.controller.templates.count == 2)
    #expect(Container.shared.sharedState().currentEpisodeID == episode.id)
  }

  @Test("leaving Now Playing cancels its pending podcast shortcut", arguments: [false, true])
  func navigationCancelsShortcut(upNext: Bool) async throws {
    let episode = try await Create.podcastEpisode()
    Container.shared.stateManager().setOnDeck(episode)
    let scene = try CarPlayPodcastScene()
    defer { scene.stop() }
    let repo = try #require(Container.shared.repo() as? FakeRepo)
    scene.controller.pushTemplate(CPNowPlayingTemplate.shared, animated: false, completion: nil)
    repo.pendingPodcastEpisodeFetchSuspend(true)
    scene.coordinator.nowPlayingTemplateAlbumArtistButtonTapped(CPNowPlayingTemplate.shared)
    try await repo.waitForPodcastEpisodeFetchSuspended()
    if upNext {
      scene.coordinator.nowPlayingTemplateUpNextButtonTapped(CPNowPlayingTemplate.shared)
    } else {
      scene.controller.goBack()
    }
    #expect(repo.cancelledPodcastEpisodeFetchCount() == 1)
    #expect(scene.controller.topTemplate === scene.root)
    await repo.resumeAllPodcastEpisodeFetchSuspensions()
    scene.controller.pushTemplate(CPNowPlayingTemplate.shared, animated: false, completion: nil)
    scene.coordinator.nowPlayingTemplateAlbumArtistButtonTapped(CPNowPlayingTemplate.shared)
    try await Wait.until(
      { @MainActor in
        (scene.controller.topTemplate as? CPListTemplate)?.sections.flatMap(\.items)
          .contains { $0.text == episode.title } == true
      },
      { "A fresh podcast shortcut must still open the current podcast" }
    )
    #expect(scene.controller.pushed.count == 3)
    #expect(scene.controller.alerts.isEmpty)
  }

  @Test("changing root tabs cancels hidden podcast artwork")
  func tabArtworkCancellation() async throws {
    let imageURL = URL.valid()
    let gate = AsyncSemaphore(value: 0)
    defer { gate.signal() }
    let entered = ThreadSafe(false)
    let cancelled = ThreadSafe(false)
    let data = FakeDataLoader.create(imageURL).pngData()!
    Container.shared.fakeDataLoader()
      .respond(to: imageURL) { _ in
        entered(true)
        return await withTaskCancellationHandler {
          await gate.wait()
          return data
        } onCancel: {
          cancelled(true)
        }
      }
    _ = try await Container.shared.repo()
      .insertSeries(
        UnsavedPodcastSeries(
          unsavedPodcast: try Create.unsavedPodcast(
            title: "Recent",
            image: imageURL,
            subscriptionDate: Date()
          ),
          unsavedEpisodes: [try Create.unsavedEpisode()]
        )
      )
    let scene = try CarPlayPodcastScene()
    defer { scene.stop() }
    try await Wait.until({ entered() }, { "Podcast artwork must load independently" })
    let row = try #require(CarPlayPodcastScene.rows(scene.podcasts).first { $0.text == "Recent" })
    scene.root.selectTemplate(at: 0)
    scene.root.delegate?.tabBarTemplate(scene.root, didSelect: scene.root.templates[0])
    try await Wait.until(
      { cancelled() },
      { "Leaving the Podcasts tab must cancel its artwork request" }
    )
    #expect(row.image == nil)
    #expect(scene.controller.templates.count == 1)
  }

  @Test("duplicate titles and publication dates have stable IDs and recent content stays short")
  func deterministicOrdering() async throws {
    let repo = Container.shared.repo()
    var ids: [Podcast.ID] = []
    for _ in 0..<12 {
      let series = try await repo.insertSeries(
        UnsavedPodcastSeries(
          unsavedPodcast: try Create.unsavedPodcast(title: "Same title", subscriptionDate: Date()),
          unsavedEpisodes: [try Create.unsavedEpisode(pubDate: Date(timeIntervalSince1970: 10))]
        )
      )
      ids.append(series.id)
    }
    let scene = try CarPlayPodcastScene()
    defer { scene.stop() }
    let all = try await scene.openAll()
    #expect(
      CarPlayPodcastScene.rows(scene.podcasts).compactMap { $0.userInfo as? Podcast.ID }
        == Array(ids.prefix(10))
    )
    #expect(CarPlayPodcastScene.rows(all).compactMap { $0.userInfo as? Podcast.ID } == ids)
  }

  @Test("real database query failures have Retry and recover without a new root")
  func queryRecovery() async throws {
    let appDB = Container.shared.appDB()
    let series = try await Container.shared.repo()
      .insertSeries(
        UnsavedPodcastSeries(
          unsavedPodcast: try Create.unsavedPodcast(title: "Retry show", subscriptionDate: Date()),
          unsavedEpisodes: [try Create.unsavedEpisode(title: "Saved episode")]
        )
      )
    try await appDB.writer.write { db in
      try db.execute(sql: "ALTER TABLE podcastTag RENAME TO unavailablePodcastTag")
    }
    let scene = try CarPlayPodcastScene()
    defer { scene.stop() }
    try await Wait.until(
      { @MainActor in CarPlayPodcastScene.rows(scene.podcasts).contains { $0.text == "Retry" } },
      { "Catalog query failure must show a native retry row" }
    )
    try await appDB.writer.write { db in
      try db.execute(sql: "ALTER TABLE unavailablePodcastTag RENAME TO podcastTag")
    }
    try CarPlayPodcastScene.tap("Retry", in: scene.podcasts)
    let all = try await scene.openAll()
    try await appDB.writer.write { db in
      try db.execute(sql: "ALTER TABLE episodeTag RENAME TO unavailableEpisodeTag")
    }
    try CarPlayPodcastScene.tap("Retry show", in: all)
    let detail = try #require(scene.controller.topTemplate as? CPListTemplate)
    try await Wait.until(
      { @MainActor in CarPlayPodcastScene.rows(detail).contains { $0.text == "Retry" } },
      { "Detail query failure must not look like an empty podcast" }
    )
    try await appDB.writer.write { db in
      try db.execute(sql: "ALTER TABLE unavailableEpisodeTag RENAME TO episodeTag")
    }
    try CarPlayPodcastScene.tap("Retry", in: detail)
    try await Wait.until(
      { @MainActor in CarPlayPodcastScene.rows(detail).contains { $0.text == "Saved episode" } },
      { "Retry must restart the real saved-data observation" }
    )
    try CarPlayPodcastScene.tap("All Episodes", in: detail)
    #expect(CarPlayPodcastScene.rows(detail).contains { $0.text == "Unfinished" })
    #expect(scene.controller.roots.count == 1)
    #expect(try await Container.shared.repo().podcast(series.id) != nil)
  }

  @Test("obsolete destinations and artwork cannot change the new page or disconnected scene")
  func staleDestinationsAndArtwork() async throws {
    let imageURL = URL.valid()
    let gate = AsyncSemaphore(value: 0)
    defer { gate.signal() }
    let entered = ThreadSafe(false)
    let returned = ThreadSafe(false)
    let data = FakeDataLoader.create(imageURL).pngData()!
    Container.shared.fakeDataLoader()
      .respond(to: imageURL) { _ in
        entered(true)
        await gate.wait()
        returned(true)
        return data
      }
    _ = try await Create.podcast(title: "Delayed art", image: imageURL, subscriptionDate: Date())
    _ = try await Create.podcast(title: "Other", subscriptionDate: Date())
    let scene = try CarPlayPodcastScene()
    defer { scene.stop() }
    let all = try await scene.openAll()
    let old = try #require(CarPlayPodcastScene.rows(all).first { $0.text == "Delayed art" })
    try await Wait.until({ entered() }, { "Text must appear while artwork is still loading" })
    #expect(old.image == nil)
    try CarPlayPodcastScene.tap("Delayed art", in: all)
    let oldDetail = try #require(scene.controller.topTemplate as? CPListTemplate)
    scene.controller.goBack()
    try CarPlayPodcastScene.tap("Other", in: all)
    let latest = try #require(scene.controller.topTemplate as? CPListTemplate)
    try await Wait.until(
      { @MainActor in CarPlayPodcastScene.rows(latest).contains { $0.text == "No saved episodes" }
      },
      { "Latest destination must settle without the old query" }
    )
    gate.signal()
    try await Wait.until({ returned() }, { "Obsolete artwork must return" })
    #expect(old.image == nil)
    #expect(oldDetail.sections.isEmpty)
    #expect(scene.controller.topTemplate === latest)
    scene.stop()
    #expect(CarPlayPodcastScene.rows(latest).allSatisfy { $0.handler == nil })
    #expect(scene.controller.delegate == nil)
  }

  @Test("artwork and playback failures leave text and native retryable selection usable")
  func artworkAndPlaybackFailure() async throws {
    let imageURL = URL.valid()
    Container.shared.fakeDataLoader().respond(to: imageURL, error: TestError.simulatedFailure)
    let series = try await Container.shared.repo()
      .insertSeries(
        UnsavedPodcastSeries(
          unsavedPodcast: try Create.unsavedPodcast(
            title: "No artwork",
            image: imageURL,
            subscriptionDate: Date()
          ),
          unsavedEpisodes: [try Create.unsavedEpisode(title: "Playable row")]
        )
      )
    await Container.shared.fakeEpisodeAssetLoader()
      .respond(to: series.episodes[0].mediaURL, error: TestError.simulatedFailure)
    let scene = try CarPlayPodcastScene()
    defer { scene.stop() }
    let detail = try await scene.open("No artwork")
    let row = try #require(CarPlayPodcastScene.rows(detail).first { $0.text == "Playable row" })
    #expect(row.image == nil)
    let completion = ThreadSafe(0)
    row.handler?(row) { completion { $0 += 1 } }
    try await Wait.until(
      { completion() == 1 },
      { "Playback failure must complete the native spinner" }
    )
    #expect(row.handler != nil)
    #expect(scene.controller.alerts.count == 1)
    #expect(scene.controller.topTemplate === detail)
    #expect(CarPlayPodcastScene.rows(detail).contains { $0.text == "Playable row" })
  }

  @Test("runtime restrictions update both podcast and episode pages within their full budget")
  func runtimeRestrictions() async throws {
    Container.shared.carPlayListLimits.context(.test) {
      { CarPlayListLimits(items: 4, sections: 1) }
    }
    var session: CPSessionConfiguration?
    Container.shared.carPlaySession.context(.test) {
      { delegate in
        let configuration = CPSessionConfiguration(delegate: delegate)
        session = configuration
        return configuration
      }
    }
    for index in 0..<6 {
      _ = try await Container.shared.repo()
        .insertSeries(
          UnsavedPodcastSeries(
            unsavedPodcast: try Create.unsavedPodcast(
              title: "Show \(index)",
              subscriptionDate: Date()
            ),
            unsavedEpisodes: try (0..<8).map { try Create.unsavedEpisode(title: "Episode \($0)") }
          )
        )
    }
    let scene = try CarPlayPodcastScene()
    defer { scene.stop() }
    let detail = try await scene.open("Show 0")
    let configuration = try #require(session)
    scene.coordinator.sessionConfiguration(configuration, limitedUserInterfacesChanged: .lists)
    #expect(scene.podcasts.itemCount == 4)
    #expect(detail.itemCount == 4)
    #expect(!CarPlayPodcastScene.rows(detail).contains { $0.text == "Next page" })
    #expect(CarPlayPodcastScene.rows(detail).last?.detailText?.contains("vehicle limits") == true)
    Container.shared.carPlayListLimits.context(.test) {
      { CarPlayListLimits(items: 0, sections: 0) }
    }
    scene.coordinator.sessionConfiguration(configuration, limitedUserInterfacesChanged: .lists)
    #expect(scene.podcasts.sections.isEmpty)
    #expect(detail.sections.isEmpty)
    #expect(detail.emptyViewTitleVariants == ["List unavailable"])
  }

  @Test("a shortcut tapped for an obsolete current episode cannot open its podcast")
  func obsoleteShortcut() async throws {
    let first = try await Create.podcastEpisode()
    let second = try await Create.podcastEpisode()
    Container.shared.stateManager().setOnDeck(first)
    let scene = try CarPlayPodcastScene()
    defer { scene.stop() }
    scene.coordinator.nowPlayingTemplateAlbumArtistButtonTapped(CPNowPlayingTemplate.shared)
    Container.shared.stateManager().setOnDeck(second)
    scene.coordinator.nowPlayingTemplateAlbumArtistButtonTapped(CPNowPlayingTemplate.shared)
    let latest = try await Wait.forValue { @MainActor in
      let top = scene.controller.topTemplate as? CPListTemplate
      return top?.sections.flatMap(\.items).contains { $0.text == second.title } == true ? top : nil
    }
    #expect(!CarPlayPodcastScene.rows(latest).contains { $0.text == first.title })
    #expect(scene.controller.pushed.count == 1)
    #expect(scene.controller.templates.count == 2)
  }
}
