// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("of OnDeckViewModel tests", .container)
@MainActor final class OnDeckViewModelTests {
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.repo) private var repo

  @Test("tagIDs(for:) returns the tag set for a tagged saved on-deck episode")
  func tagIDsExposesSavedEpisodeTags() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [try Create.unsavedEpisode()]
      )
    )
    let episodeID = series.episodes[0].id
    let tagOne = try await repo.insertTag(UnsavedTag(name: "Alpha"))
    let tagTwo = try await repo.insertTag(UnsavedTag(name: "Beta"))
    try await repo.addTag(tagOne.id, to: episodeID)
    try await repo.addTag(tagTwo.id, to: episodeID)

    let onDeck = try #require(try await observatory.onDeck(episodeID).get())

    let viewModel = OnDeckViewModel()
    #expect(viewModel.tagIDs(for: onDeck) == [tagOne.id, tagTwo.id])
  }
}
