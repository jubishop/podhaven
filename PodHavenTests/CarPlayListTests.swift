// Copyright Justin Bishop, 2026

import AVFoundation
import CarPlay
import FactoryKit
import FactoryTesting
import Foundation
import Semaphore
import Testing

@testable import PodHaven

@Suite("of CarPlay list tests", .container)
@MainActor struct CarPlayListTests {
  @Test("paging includes navigation rows in the item budget without changing the queue")
  func paging() async throws {
    Container.shared.carPlayListLimits.context(.test) {
      { CarPlayListLimits(items: 4, sections: 1) }
    }
    var episodes: [CarPlayEpisodeRow] = []
    for index in 0..<7 {
      let episode = try await Create.podcastEpisode(
        Create.unsavedEpisode(title: "Episode \(index)")
      )
      episodes.append(CarPlayEpisodeRow(OnDeck(from: episode)))
    }
    let template = CPListTemplate(title: "Up Next", sections: [])
    let list = CarPlayEpisodeList(
      template: template,
      selection: Container.shared.carPlaySelection()
    )
    defer { list.stop() }
    list.update([.init(title: "Queue", episodes: episodes)], restricted: false)
    #expect(template.itemCount == 3)
    #expect(template.sections.count == 1)
    var seen = Set<String>()
    for _ in 0..<4 {
      let items = template.sections.flatMap(\.items).compactMap { $0 as? CPListItem }
      #expect(items.count <= 4)
      seen.formUnion(items.compactMap(\.text).filter { $0.hasPrefix("Episode") })
      if let next = items.first(where: { $0.text == "Next page" }) { next.handler?(next) {} }
    }
    #expect(seen == Set(episodes.map(\.title)))
    let previous = try #require(
      template.sections.flatMap(\.items).compactMap { $0 as? CPListItem }
        .first { $0.text == "Previous page" }
    )
    previous.handler?(previous) {}
    #expect(template.sections.flatMap(\.items).first?.text == "Episode 4")
    list.update([.init(title: "Queue", episodes: episodes)], restricted: true)
    #expect(template.itemCount == 4)
    #expect(template.sections.flatMap(\.items).allSatisfy { !($0.text ?? "").contains("page") })
    #expect(
      (template.sections.flatMap(\.items).last as? CPListItem)?.detailText?
        .contains("vehicle limits") == true
    )
    #expect(Container.shared.sharedState().queuedPodcastEpisodes.isEmpty)
    Container.shared.carPlayListLimits.context(.test) {
      { CarPlayListLimits(items: 0, sections: 0) }
    }
    list.update([.init(title: "Queue", episodes: episodes)], restricted: false)
    #expect(template.itemCount == 0)
    #expect(template.sections.isEmpty)
  }

  @Test("native rows retain identity and useful progress and download text")
  func semantics() async throws {
    let episode = try await Create.podcastEpisode(
      Create.unsavedEpisode(
        duration: .seconds(120),
        currentTime: .seconds(30),
        cachedFilename: "download.mp3"
      )
    )
    Container.shared.stateManager().setOnDeck(episode)
    let template = CPListTemplate(title: "Up Next", sections: [])
    let list = CarPlayEpisodeList(
      template: template,
      selection: Container.shared.carPlaySelection()
    )
    defer { list.stop() }
    let sections = [
      CarPlayEpisodeList.Section(
        title: "Current",
        episodes: [CarPlayEpisodeRow(OnDeck(from: episode))]
      )
    ]
    list.update(sections, restricted: false)
    let item = try #require(template.sections.first?.items.first as? CPListItem)
    #expect(item.playbackProgress == 0.25)
    #expect(item.detailText?.contains("Downloaded") == true)
    #expect(item.detailText?.contains("Current episode") == true)
    #expect(!item.isPlaying)
    Container.shared.sharedState().setPlaybackStatus(.playing)
    list.update(sections, restricted: false)
    #expect(template.sections.first?.items.first === item)
    #expect(item.isPlaying)
    #expect(item.handler != nil)
    list.stop()
    #expect(item.handler == nil)
  }

  @Test("obsolete artwork cannot mutate a removed row or its replacement")
  func artwork() async throws {
    let episode = try await Create.podcastEpisode()
    let gate = AsyncSemaphore(value: 0)
    defer { gate.signal() }
    let entered = ThreadSafe(false)
    let returned = ThreadSafe(false)
    let data = FakeDataLoader.create(episode.image).pngData()!
    Container.shared.fakeDataLoader()
      .respond(to: episode.image) { _ in
        entered(true)
        await gate.wait()
        returned(true)
        return data
      }
    let template = CPListTemplate(title: "Up Next", sections: [])
    let list = CarPlayEpisodeList(
      template: template,
      selection: Container.shared.carPlaySelection()
    )
    defer { list.stop() }
    list.update(
      [.init(title: "Queue", episodes: [CarPlayEpisodeRow(OnDeck(from: episode))])],
      restricted: false
    )
    let old = try #require(template.sections.first?.items.first as? CPListItem)
    try await Wait.until({ entered() }, { "Artwork must begin loading independently" })
    #expect(old.text == episode.title)
    #expect(old.image == nil)
    list.update([], restricted: false)
    gate.signal()
    try await Wait.until({ returned() }, { "Old artwork must finish" })
    #expect(old.image == nil)
    #expect(old.handler == nil)
    #expect(template.sections.isEmpty)
  }

  @Test("recommendations preserve ranking, eligibility, zero limit, and live settings")
  func recommendations() async throws {
    let first = try await Create.podcastEpisode()
    let second = try await Create.podcastEpisode()
    let ineligible = try await Create.podcastEpisode(
      Create.unsavedEpisode(currentTime: .seconds(1))
    )
    let state = Container.shared.sharedState()
    let settings = Container.shared.userSettings()
    settings.$maxRecommendedEpisodesInUpNext.new(2)
    state.setRecommendedEpisodePool([second.id, ineligible.id, first.id])
    let coordinator = Container.shared.carPlayCoordinator()
    let controller = FakeCarPlayInterfaceController()
    coordinator.connect(controller)
    defer { coordinator.disconnect(controller) }
    controller.completions[0](true, nil)
    let root = try #require(controller.roots.first as? CPTabBarTemplate)
    let template = try #require(root.templates.first as? CPListTemplate)
    try await Wait.until(
      { await template.itemCount == 2 },
      { "Eligible recommendations must appear" }
    )
    #expect(template.sections.flatMap(\.items).map(\.text) == [second.title, first.title])
    settings.$maxRecommendedEpisodesInUpNext.new(0)
    try await Wait.until({ await template.itemCount == 0 }, { "Zero must hide recommendations" })
    settings.$maxRecommendedEpisodesInUpNext.new(1)
    try await Wait.until({ await template.itemCount == 1 }, { "Limit change must be live" })
    #expect(template.sections.flatMap(\.items).first?.text == second.title)
    _ = try await Container.shared.repo().updateRating(second.id, rating: .liked)
    try await Wait.until(
      { @MainActor in template.sections.flatMap(\.items).first?.text == first.title },
      { "Rating must remove ineligible recommendation" }
    )
    #expect(controller.roots.count == 1)
    #expect(await Container.shared.fakeAudioSession().activeCalls.isEmpty)
  }
}
