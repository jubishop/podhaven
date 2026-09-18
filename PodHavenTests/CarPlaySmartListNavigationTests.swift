// Copyright Justin Bishop, 2026

import CarPlay
import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of CarPlay Smart List navigation tests", .container)
@MainActor struct CarPlaySmartListNavigationTests {
  @Test("live sort, ordering, icons and optional unread counts follow the shared library")
  func livePreferences() async throws {
    try await CarPlaySmartListScene.clear()
    let list = try await CarPlaySmartListScene.insert("Live")
    _ = try await CarPlaySmartListScene.insert("No badge", order: 1, badge: false)
    let first = try await CarPlaySmartListScene.episode(
      Create.unsavedEpisode(title: "Old", pubDate: Date(timeIntervalSince1970: 10))
    )
    let second = try await CarPlaySmartListScene.episode(
      Create.unsavedEpisode(title: "New", pubDate: Date(timeIntervalSince1970: 20))
    )
    let scene = try CarPlaySmartListScene()
    defer { scene.stop() }
    let detail = try await scene.open("Live")
    #expect(
      CarPlaySmartListScene.rows(detail).compactMap { $0.userInfo as? Episode.ID } == [
        second.id, first.id,
      ]
    )
    try await Wait.until(
      { @MainActor in CarPlaySmartListScene.rows(scene.hub).first?.detailText == "2 unread" },
      { "Enabled counts must use the saved watermark" }
    )
    #expect(CarPlaySmartListScene.rows(scene.hub).first?.image != nil)
    #expect(CarPlaySmartListScene.rows(scene.hub).last?.detailText == nil)
    try await Container.shared.smartListRepo().updateSortMethod(list.id, to: .oldestFirst)
    try await Wait.until(
      { @MainActor in
        CarPlaySmartListScene.rows(detail).compactMap { $0.userInfo as? Episode.ID } == [
          first.id, second.id,
        ]
      },
      { "Live sort changes must reorder the open list" }
    )
    try await Container.shared.smartListRepo().moveSmartList(list.id, to: 2)
    try await Wait.until(
      { @MainActor in CarPlaySmartListScene.rows(scene.hub).last?.text == "Live" },
      { "Live configured ordering must update without replacing the root" }
    )
    #expect(scene.controller.topTemplate === detail)
  }

  @Test("vehicle restrictions include every section and control in the item budget")
  func restrictions() async throws {
    try await CarPlaySmartListScene.clear()
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
    for index in 0..<7 {
      _ = try await CarPlaySmartListScene.insert("List \(index)", order: index)
      _ = try await CarPlaySmartListScene.episode(Create.unsavedEpisode(title: "Episode \(index)"))
    }
    let scene = try CarPlaySmartListScene()
    defer { scene.stop() }
    let detail = try await scene.open("List 0")
    let configuration = try #require(session)
    scene.coordinator.sessionConfiguration(configuration, limitedUserInterfacesChanged: .lists)
    #expect(scene.hub.itemCount == 4)
    #expect(detail.itemCount == 4)
    #expect(
      CarPlaySmartListScene.rows(scene.hub).last?.detailText?.contains("vehicle limits") == true
    )
    #expect(CarPlaySmartListScene.rows(detail).last?.detailText?.contains("vehicle limits") == true)
    #expect(!CarPlaySmartListScene.rows(detail).contains { $0.text == "Next page" })
    Container.shared.carPlayListLimits.context(.test) {
      { CarPlayListLimits(items: 0, sections: 0) }
    }
    scene.coordinator.sessionConfiguration(configuration, limitedUserInterfacesChanged: .lists)
    #expect(detail.itemCount == 0)
    #expect(scene.hub.itemCount == 0)
    #expect(scene.hub.emptyViewTitleVariants == ["List unavailable"])
    #expect(detail.emptyViewTitleVariants == ["List unavailable"])
  }

  @Test("failed navigation does not mark a list seen and can be retried")
  func rejectedNavigation() async throws {
    try await CarPlaySmartListScene.clear()
    let list = try await CarPlaySmartListScene.insert("Retry")
    _ = try await CarPlaySmartListScene.episode(Create.unsavedEpisode(title: "Saved"))
    let scene = try CarPlaySmartListScene()
    defer { scene.stop() }
    try await Wait.until(
      { @MainActor in CarPlaySmartListScene.rows(scene.hub).first?.text == "Retry" },
      { "Saved list must load" }
    )
    scene.controller.pushResult = false
    try CarPlaySmartListScene.tap("Retry", in: scene.hub)
    #expect(scene.controller.topTemplate === scene.root)
    #expect(scene.controller.alerts.count == 1)
    #expect(try await Container.shared.smartListRepo().fetchOne(list.id)?.lastSeenEpisodeId == 0)
    scene.controller.pushResult = true
    let detail = try await scene.open("Retry")
    #expect(CarPlaySmartListScene.rows(detail).first?.text == "Saved")
    scene.controller.popResult = false
    try await Container.shared.smartListRepo().delete(list.id)
    try await Wait.until(
      { @MainActor in detail.emptyViewTitleVariants == ["No Smart Lists"] },
      { "Rejected return must still remove deleted content in place" }
    )
    #expect(scene.controller.topTemplate === detail)
    #expect(detail.itemCount == 0)
  }

  @Test("catalog query failures have a Retry path and restore saved lists")
  func catalogFailure() async throws {
    let db = Container.shared.appDB()
    try await db.writer.write { db in
      try db.execute(sql: "ALTER TABLE smartList RENAME TO unavailableSmartList")
    }
    let scene = try CarPlaySmartListScene()
    defer { scene.stop() }
    try await Wait.until(
      { @MainActor in CarPlaySmartListScene.rows(scene.hub).contains { $0.text == "Retry" } },
      { "Catalog failure must expose Retry" }
    )
    try await db.writer.write { db in
      try db.execute(sql: "ALTER TABLE unavailableSmartList RENAME TO smartList")
    }
    try CarPlaySmartListScene.tap("Retry", in: scene.hub)
    try await Wait.until(
      { @MainActor in
        CarPlaySmartListScene.rows(scene.hub).contains { $0.text == "Recent Episodes" }
      },
      { "Catalog Retry must restart both list and count observations" }
    )
    #expect(scene.controller.roots.count == 1)
  }
}
