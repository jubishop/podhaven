// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("of TagsSettingsViewModel tests", .container)
@MainActor final class TagsSettingsViewModelTests {
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.repo) private var repo

  @Test("deleteTag asks first before counts load, keeps a tag on Cancel, deletes one on Delete")
  func deleteTagConfirmsBeforeDeletingEvenWhenCountsHaveNotLoaded() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [try Create.unsavedEpisode()]
      )
    )
    let kept = try await repo.insertTag(UnsavedTag(name: "Listen Later"))
    let deleted = try await repo.insertTag(UnsavedTag(name: "Favorites"))
    try await repo.addTag(kept.id, to: series.episodes[0].id)
    try await repo.addTag(deleted.id, to: series.episodes[0].id)
    let viewModel = TagsSettingsViewModel()

    viewModel.deleteTag(kept.id)
    let cancelled = try await answerAlert("Cancel")

    #expect(cancelled.title == "Delete Tag?")
    #expect(try await observatory.tags().get()[id: kept.id] != nil)

    viewModel.deleteTag(deleted.id)
    try await answerAlert("Delete")

    try await Wait.until(
      { @MainActor in try await self.observatory.tags().get()[id: deleted.id] == nil },
      { "Expected Delete to remove tag \(deleted.id)" }
    )
    #expect(try await observatory.tags().get()[id: kept.id] != nil)
  }
}
