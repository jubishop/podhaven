// Copyright Justin Bishop, 2026

import CarPlay
import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@MainActor
struct CarPlaySmartListScene {
  let coordinator = Container.shared.carPlayCoordinator()
  let controller = FakeCarPlayInterfaceController()
  let root: CPTabBarTemplate
  let hub: CPListTemplate

  init() throws {
    coordinator.connect(controller)
    controller.completions[0](true, nil)
    root = try #require(controller.roots.first as? CPTabBarTemplate)
    hub = try #require(root.templates[1] as? CPListTemplate)
    root.selectTemplate(at: 1)
    root.delegate?.tabBarTemplate(root, didSelect: hub)
  }

  func stop() { coordinator.disconnect(controller) }

  static func rows(_ template: CPListTemplate) -> [CPListItem] {
    template.sections.flatMap(\.items).compactMap { $0 as? CPListItem }
  }

  static func tap(_ title: String, in template: CPListTemplate) throws {
    let row = try #require(rows(template).first { $0.text == title })
    let handler = try #require(row.handler)
    handler(row) {}
  }

  func open(_ title: String) async throws -> CPListTemplate {
    try await Wait.until(
      { @MainActor in Self.rows(hub).contains { $0.text == title } },
      { "Saved Smart Lists must appear in Episodes" }
    )
    try Self.tap(title, in: hub)
    let detail = try #require(controller.topTemplate as? CPListTemplate)
    try #require(detail !== hub)
    try await Wait.until(
      { @MainActor in !detail.showsSpinnerWhileEmpty },
      { "Smart List query must settle" }
    )
    return detail
  }

  static func episode(_ episode: UnsavedEpisode) async throws -> PodcastEpisode {
    try await Container.shared.repo()
      .upsertPodcastEpisode(
        UnsavedPodcastEpisode(unsavedPodcast: try Create.unsavedPodcast(), unsavedEpisode: episode)
      )
  }

  static func clear() async throws {
    try await Container.shared.appDB().writer
      .write { db in
        _ = try SmartList.deleteAll(db)
      }
  }

  static func insert(
    _ title: String,
    order: Int = 0,
    sort: SmartListSortMethod = .newestFirst,
    filter: SmartListFilter = SmartListFilter(),
    badge: Bool = true
  ) async throws -> SmartList {
    try await Container.shared.smartListRepo()
      .insert(
        try UnsavedSmartList(
          title: title,
          filter: filter,
          displayOrder: order,
          sortMethod: sort,
          showUnreadBadge: badge
        )
      )
  }
}

@Suite("of CarPlay Smart List tests", .container)
@MainActor struct CarPlaySmartListTests {
  @Test("configured list ordering, optional counts and paging retain every saved list")
  func hubPaging() async throws {
    try await CarPlaySmartListScene.clear()
    Container.shared.carPlayListLimits.context(.test) {
      { CarPlayListLimits(items: 4, sections: 1) }
    }
    var lists: [SmartList] = []
    for index in 0..<7 {
      lists.append(try await CarPlaySmartListScene.insert("List \(index)", order: 6 - index))
    }
    let scene = try CarPlaySmartListScene()
    defer { scene.stop() }
    try await Wait.until(
      { @MainActor in CarPlaySmartListScene.rows(scene.hub).first?.text == "List 6" },
      { "Configured display order must apply" }
    )
    var ids: [SmartList.ID] = []
    for _ in 0..<4 {
      #expect(scene.hub.itemCount <= 4)
      ids += CarPlaySmartListScene.rows(scene.hub).compactMap { $0.userInfo as? SmartList.ID }
      if CarPlaySmartListScene.rows(scene.hub).contains(where: { $0.text == "Next page" }) {
        try CarPlaySmartListScene.tap("Next page", in: scene.hub)
      }
    }
    #expect(ids == lists.reversed().map(\.id))
    #expect(scene.controller.templates.count == 1)
    #expect(await Container.shared.fakeAudioSession().activeCalls.isEmpty)
  }

  @Test(
    "all standard sorts apply their membership filter with stable episode ties",
    arguments: SmartListSortMethod.allCases.filter { $0 != .recommendationScore }
  )
  func standardSorts(sort: SmartListSortMethod) async throws {
    try await CarPlaySmartListScene.clear()
    let date = Date(timeIntervalSince1970: 200)
    let series = try await Container.shared.repo()
      .insertSeries(
        UnsavedPodcastSeries(
          unsavedPodcast: try Create.unsavedPodcast(),
          unsavedEpisodes: [
            try Create.unsavedEpisode(
              title: "First",
              pubDate: date,
              duration: .seconds(100),
              finishDate: date,
              queueDate: date
            ),
            try Create.unsavedEpisode(
              title: "Second",
              pubDate: date,
              duration: .seconds(100),
              finishDate: date,
              queueDate: date
            ),
            try Create.unsavedEpisode(title: "Excluded", pubDate: date, duration: .seconds(100)),
          ]
        )
      )
    _ = try await CarPlaySmartListScene.insert("Sorted", sort: sort)
    let scene = try CarPlaySmartListScene()
    defer { scene.stop() }
    let detail = try await scene.open("Sorted")
    let expected = try await Container.shared.appDB().reader
      .read { db in
        try Episode.filter(sort.sqlFilter)
          .order([sort.sqlOrdering ?? Episode.Columns.id.asc, Episode.Columns.id.asc])
          .fetchAll(db).map(\.id)
      }
    #expect(
      CarPlaySmartListScene.rows(detail).compactMap { $0.userInfo as? Episode.ID } == expected
    )
    #expect(expected.count == (sort == .recentlyFinished || sort == .recentlyQueued ? 2 : 3))
    #expect(series.episodes.count == 3)
  }

  @Test("live definitions replace membership and title, and deletion returns to Episodes")
  func definitionsAndDeletion() async throws {
    try await CarPlaySmartListScene.clear()
    _ = try await CarPlaySmartListScene.episode(Create.unsavedEpisode(title: "Unfinished"))
    let list = try await CarPlaySmartListScene.insert("Live")
    let scene = try CarPlaySmartListScene()
    defer { scene.stop() }
    let detail = try await scene.open("Live")
    try #require(CarPlaySmartListScene.rows(detail).contains { $0.text == "Unfinished" })
    try await Container.shared.smartListRepo()
      .update(
        list.id,
        title: "Finished only",
        filter: SmartListFilter(conditions: [.state(.isFinished)]),
        showUnreadBadge: false,
        alwaysShowPodcastImage: false,
        icon: .heart
      )
    try await Wait.until(
      { @MainActor in
        detail.itemCount == 0 && !detail.showsSpinnerWhileEmpty
          && CarPlaySmartListScene.rows(scene.hub).first?.text == "Finished only"
      },
      { "Updated definition must replace obsolete results and title" }
    )
    #expect(detail.emptyViewTitleVariants == ["No matching episodes"])
    try await Container.shared.smartListRepo().delete(list.id)
    try await Wait.until(
      { @MainActor in scene.controller.topTemplate === scene.root },
      { "Deleting the visible list must return to Episodes" }
    )
  }

  @Test("nested Now Playing and disconnect preserve unread until Back reaches the hub")
  func unreadNavigation() async throws {
    try await CarPlaySmartListScene.clear()
    let list = try await CarPlaySmartListScene.insert("Unread")
    let episode = try await CarPlaySmartListScene.episode(Create.unsavedEpisode(title: "Current"))
    await Container.shared.appLauncher().prepareForPlayback()
    try await Container.shared.playManager().load(episode)
    let scene = try CarPlaySmartListScene()
    defer { scene.stop() }
    let detail = try await scene.open("Unread")
    #expect(try await Container.shared.smartListRepo().fetchOne(list.id)?.lastSeenEpisodeId == 0)
    try CarPlaySmartListScene.tap("Current", in: detail)
    try await Wait.until(
      { @MainActor in scene.controller.topTemplate === CPNowPlayingTemplate.shared },
      { "Smart List selection must use the shared Now Playing flow" }
    )
    #expect(try await Container.shared.smartListRepo().fetchOne(list.id)?.lastSeenEpisodeId == 0)
    scene.controller.goBack()
    #expect(scene.controller.topTemplate === detail)
    #expect(try await Container.shared.smartListRepo().fetchOne(list.id)?.lastSeenEpisodeId == 0)
    scene.controller.goBack()
    try await Wait.until(
      {
        try await Container.shared.smartListRepo().fetchOne(list.id)?.lastSeenEpisodeId
          == episode.id
      },
      { "Only returning to the hub marks the list seen" }
    )
    let later = try await CarPlaySmartListScene.episode(Create.unsavedEpisode(title: "Later"))
    _ = try await scene.open("Unread")
    scene.stop()
    #expect(
      try await Container.shared.smartListRepo().fetchOne(list.id)?.lastSeenEpisodeId != later.id
    )
  }

  @Test("deletion below Now Playing leaves playback and a valid Back destination")
  func hiddenDeletion() async throws {
    try await CarPlaySmartListScene.clear()
    let list = try await CarPlaySmartListScene.insert("Deleted")
    _ = try await CarPlaySmartListScene.insert("Remaining", order: 1)
    _ = try await CarPlaySmartListScene.episode(Create.unsavedEpisode(title: "Episode"))
    let scene = try CarPlaySmartListScene()
    defer { scene.stop() }
    let detail = try await scene.open("Deleted")
    scene.controller.pushTemplate(CPNowPlayingTemplate.shared, animated: false, completion: nil)
    try await Container.shared.smartListRepo().delete(list.id)
    try await Wait.until(
      { @MainActor in CarPlaySmartListScene.rows(detail).contains { $0.text == "Remaining" } },
      { "Deleted hidden detail must become a valid Episodes hub" }
    )
    #expect(scene.controller.topTemplate === CPNowPlayingTemplate.shared)
    scene.controller.goBack()
    #expect(!CarPlaySmartListScene.rows(detail).contains { $0.text == "Episode" })
    try CarPlaySmartListScene.tap("Remaining", in: detail)
    #expect(scene.controller.templates.count == 2)
  }
}
