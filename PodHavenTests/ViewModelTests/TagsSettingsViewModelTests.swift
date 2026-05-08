// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("of TagsSettingsViewModel tests", .container)
@MainActor final class TagsSettingsViewModelTests {
  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.repo) private var repo

  @Test("deleteTag confirms before deleting even when counts have not loaded")
  func deleteTagConfirmsBeforeDeletingEvenWhenCountsHaveNotLoaded() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [try Create.unsavedEpisode()]
      )
    )
    let tag = try await repo.insertTag(UnsavedTag(name: "Listen Later"))
    try await repo.addTag(tag.id, to: series.episodes[0].id)
    let viewModel = TagsSettingsViewModel()

    viewModel.deleteTag(tag.id)

    #expect(alert.config?.title == "Delete Tag?")
    let tagsAfter = try await observatory.tags().get()
    #expect(tagsAfter[id: tag.id] != nil)
  }
}
