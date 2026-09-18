// Copyright Justin Bishop, 2026

import CarPlay
import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of CarPlay podcast tests", .container)
@MainActor struct CarPlayPodcastTests {
  @Test("recent podcasts use saved publication dates and All Podcasts includes empty shows")
  func savedOrdering() async throws {
    let repo = Container.shared.repo()
    let older = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(
          title: "Zulu",
          lastUpdate: Date(),
          subscriptionDate: Date()
        ),
        unsavedEpisodes: [try Create.unsavedEpisode(pubDate: Date(timeIntervalSince1970: 1))]
      )
    )
    let newer = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(title: "Alpha", subscriptionDate: Date()),
        unsavedEpisodes: [try Create.unsavedEpisode(pubDate: Date(timeIntervalSince1970: 2))]
      )
    )
    _ = try await Create.podcast(title: "Empty", subscriptionDate: Date())
    _ = try await Create.podcast(title: "Not subscribed")
    let coordinator = Container.shared.carPlayCoordinator()
    let controller = FakeCarPlayInterfaceController()
    coordinator.connect(controller)
    defer { coordinator.disconnect(controller) }
    controller.completions[0](true, nil)
    let root = try #require(controller.roots.first as? CPTabBarTemplate)
    let podcasts = try #require(root.templates.last as? CPListTemplate)
    try await Wait.until(
      { @MainActor in podcasts.sections.flatMap(\.items).contains { $0.text == "All Podcasts" } },
      { "Podcasts must expose saved subscribed shows and All Podcasts" }
    )
    #expect(
      podcasts.sections.flatMap(\.items).map(\.text) == [
        "All Podcasts", newer.podcast.title, older.podcast.title,
      ]
    )
    let all = try #require(podcasts.sections.first?.items.first as? CPListItem)
    all.handler?(all) {}
    let alphabetical = try #require(controller.topTemplate as? CPListTemplate)
    #expect(alphabetical.sections.flatMap(\.items).map(\.text) == ["Alpha", "Empty", "Zulu"])
    #expect(await Container.shared.fakeAudioSession().activeCalls.isEmpty)
  }

  @Test("Now Playing enables its shortcut for an unsubscribed saved current podcast")
  func currentPodcastAvailability() async throws {
    let episode = try await Create.podcastEpisode()
    Container.shared.stateManager().setOnDeck(episode)
    let coordinator = Container.shared.carPlayCoordinator()
    let controller = FakeCarPlayInterfaceController()
    coordinator.connect(controller)
    defer { coordinator.disconnect(controller) }
    controller.completions[0](true, nil)
    try await Wait.until(
      { @MainActor in Container.shared.carPlayNowPlaying().isAlbumArtistButtonEnabled },
      { "A saved current podcast must enable the shortcut without subscribing" }
    )
    #expect(try await Container.shared.repo().podcast(episode.podcast.id)?.subscriptionDate == nil)
  }
}
