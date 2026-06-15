// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("of TagEditorViewModel tests", .container)
@MainActor final class TagEditorViewModelTests {
  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.sharedState) private var sharedState

  @Test("save persists a trimmed name and the chosen icon")
  func savePersistsNameAndIcon() async throws {
    let tag = try await repo.insertTag(UnsavedTag(name: "news"))
    sharedState.setTags([tag])
    let viewModel = TagEditorViewModel(tag: tag, podcastCount: 0, episodeCount: 0)
    viewModel.name = "  Tech  "
    viewModel.icon = .cpu

    #expect(viewModel.canSave)
    viewModel.save()

    try await Wait.until(
      { @MainActor in try await self.observatory.tags().get()[id: tag.id]?.name == "Tech" },
      { "Expected save to persist the trimmed name" }
    )
    let updated = try #require(try await observatory.tags().get()[id: tag.id])
    #expect(updated.name == "Tech")
    #expect(updated.icon == .cpu)
    #expect(alert.config == nil)
  }

  @Test("a case-insensitive duplicate name alerts and skips the write")
  func duplicateNameAlertsAndSkipsWrite() async throws {
    let news = try await repo.insertTag(UnsavedTag(name: "News"))
    let tech = try await repo.insertTag(UnsavedTag(name: "Tech"))
    sharedState.setTags([news, tech])
    let viewModel = TagEditorViewModel(tag: tech, podcastCount: 0, episodeCount: 0)
    viewModel.name = "news"

    viewModel.save()

    // The conflict check runs synchronously before any write Task is spawned.
    #expect(alert.config != nil)
    #expect(try await observatory.tags().get()[id: tech.id]?.name == "Tech")
  }

  @Test("changing only the icon keeps the same name without a conflict")
  func iconOnlyEditKeepsSameName() async throws {
    let tag = try await repo.insertTag(UnsavedTag(name: "News"))
    sharedState.setTags([tag])
    let viewModel = TagEditorViewModel(tag: tag, podcastCount: 0, episodeCount: 0)
    viewModel.icon = .newspaper

    viewModel.save()

    try await Wait.until(
      { @MainActor in try await self.observatory.tags().get()[id: tag.id]?.icon == .newspaper },
      { "Expected the icon-only edit to persist" }
    )
    #expect(try await observatory.tags().get()[id: tag.id]?.name == "News")
    #expect(alert.config == nil)
  }

  @Test("a blank name cannot be saved")
  func blankNameCannotBeSaved() async throws {
    let tag = try await repo.insertTag(UnsavedTag(name: "News"))
    sharedState.setTags([tag])
    let viewModel = TagEditorViewModel(tag: tag, podcastCount: 0, episodeCount: 0)
    viewModel.name = "   "

    #expect(!viewModel.canSave)
    viewModel.save()
    #expect(try await observatory.tags().get()[id: tag.id]?.name == "News")
  }

  @Test("deleteTag confirms before deleting")
  func deleteTagConfirmsBeforeDeleting() async throws {
    let tag = try await repo.insertTag(UnsavedTag(name: "News"))
    let viewModel = TagEditorViewModel(tag: tag, podcastCount: 2, episodeCount: 1)

    viewModel.deleteTag()

    #expect(alert.config?.title == "Delete Tag?")
    #expect(try await observatory.tags().get()[id: tag.id] != nil)
  }
}
