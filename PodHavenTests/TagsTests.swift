// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of Tag model and repo tests", .container)
class TagsTests {
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.repo) private var repo

  @Test("insertTag() trims and throws on case-insensitive duplicates")
  func insertTagThrowsOnDuplicate() async throws {
    _ = try await repo.insertTag(named: "  Swift  ")

    await #expect(throws: DatabaseError.self) {
      _ = try await self.repo.insertTag(named: "swift")
    }

    let tags = try await observatory.tags().get()
    #expect(tags.map(\.name) == ["Swift"])
  }

  @Test("insertTag() throws on empty string")
  func insertTagThrowsOnEmpty() async throws {
    await #expect(throws: DatabaseError.self) {
      _ = try await self.repo.insertTag(named: "")
    }

    await #expect(throws: DatabaseError.self) {
      _ = try await self.repo.insertTag(named: "   ")
    }

    let tags = try await observatory.tags().get()
    #expect(tags.isEmpty)
  }

  @Test("observatory.tags() returns tags ordered by case-insensitive name")
  func tagsReturnsOrdered() async throws {
    _ = try await repo.insertTag(named: "zeta")
    _ = try await repo.insertTag(named: "Alpha")
    _ = try await repo.insertTag(named: "beta")

    let tags = try await observatory.tags().get()
    #expect(tags.map(\.name) == ["Alpha", "beta", "zeta"])
  }

  @Test("addTag() throws on duplicate and removeTag() unassigns")
  func assignAndUnassignTags() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: try Create.unsavedPodcast())
    )

    let tag = try await repo.insertTag(named: "Tech")
    try await repo.addTag(tag.id, to: series.id)

    await #expect(throws: DatabaseError.self) {
      _ = try await self.repo.addTag(tag.id, to: series.id)
    }

    let fetchedSeries = try await repo.podcastSeries(series.id)
    #expect(fetchedSeries?.tags?.map(\.id) == [tag.id])

    let firstRemove = try await repo.removeTag(tag.id, from: series.id)
    let secondRemove = try await repo.removeTag(tag.id, from: series.id)

    #expect(firstRemove)
    #expect(!secondRemove)
    let afterRemove = try await repo.podcastSeries(series.id)
    #expect(afterRemove?.tags?.isEmpty == true)
  }

  @Test("podcastSeries() includes associated tags")
  func podcastSeriesIncludesTags() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: try Create.unsavedPodcast())
    )

    let tagOne = try await repo.insertTag(named: "beta")
    let tagTwo = try await repo.insertTag(named: "Alpha")

    _ = try await repo.addTag(tagOne.id, to: series.id)
    _ = try await repo.addTag(tagTwo.id, to: series.id)

    let fetchedSeries = try await repo.podcastSeries(series.id)
    #expect(fetchedSeries != nil)
    #expect(fetchedSeries?.tags?.map(\.name) == ["Alpha", "beta"])
  }

  @Test("allPodcastSeries(includeTags:) controls whether tags are fetched")
  func allPodcastSeriesIncludeTagsFlag() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: try Create.unsavedPodcast())
    )
    let tag = try await repo.insertTag(named: "Tech")
    _ = try await repo.addTag(tag.id, to: series.id)

    let withoutTags = try await repo.allPodcastSeries(
      AppDB.NoOp,
      order: Podcast.Columns.id.asc,
      limit: Int.max,
      includeTags: false
    )
    #expect(withoutTags.count == 1)
    #expect(withoutTags[0].tags == nil)

    let withTags = try await repo.allPodcastSeries(
      AppDB.NoOp,
      order: Podcast.Columns.id.asc,
      limit: Int.max,
      includeTags: true
    )
    #expect(withTags.count == 1)
    #expect(withTags[0].tags?.map(\.name) == ["Tech"])
  }

  @Test("renameTag() updates name and preserves podcast associations")
  func renameTagPreservesAssociations() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: try Create.unsavedPodcast())
    )
    let tag = try await repo.insertTag(named: "news")
    try await repo.addTag(tag.id, to: series.id)

    let renamed = try await repo.renameTag(tag.id, newName: "News")
    #expect(renamed)

    let tags = try await observatory.tags().get()
    #expect(tags.map(\.name) == ["News"])

    let fetchedSeries = try await repo.podcastSeries(series.id)
    #expect(fetchedSeries?.tags?.map(\.id) == [tag.id])
  }

  @Test("renameTag() throws on conflict with another tag")
  func renameTagThrowsOnConflict() async throws {
    _ = try await repo.insertTag(named: "News")
    let tech = try await repo.insertTag(named: "Tech")

    await #expect(throws: DatabaseError.self) {
      _ = try await self.repo.renameTag(tech.id, newName: "news")
    }

    let tags = try await observatory.tags().get()
    #expect(tags.map(\.name) == ["News", "Tech"])
  }

  @Test("observatory.podcastCountsByTag() returns correct counts per tag")
  func podcastCountsByTag() async throws {
    let seriesA = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: try Create.unsavedPodcast())
    )
    let seriesB = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: try Create.unsavedPodcast())
    )

    let tagOne = try await repo.insertTag(named: "News")
    let tagTwo = try await repo.insertTag(named: "Tech")
    _ = try await repo.insertTag(named: "Empty")

    try await repo.addTag(tagOne.id, to: seriesA.id)
    try await repo.addTag(tagOne.id, to: seriesB.id)
    try await repo.addTag(tagTwo.id, to: seriesA.id)

    let counts = try await observatory.podcastCountsByTag().get()
    #expect(counts[tagOne.id] == 2)
    #expect(counts[tagTwo.id] == 1)
    #expect(counts[tagOne.id] != nil)
    #expect(counts.count == 2)
  }

  @Test("deleteTag() cascades through podcastTag mappings")
  func deletingTagRemovesPodcastMappings() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: try Create.unsavedPodcast())
    )
    let tag = try await repo.insertTag(named: "News")

    _ = try await repo.addTag(tag.id, to: series.id)
    let beforeDelete = try await repo.podcastSeries(series.id)
    #expect(beforeDelete?.tags?.count == 1)

    let deleted = try await repo.deleteTag(tag.id)
    #expect(deleted)
    let afterDelete = try await repo.podcastSeries(series.id)
    #expect(afterDelete?.tags?.isEmpty == true)
    #expect(try await observatory.tags().get().isEmpty)
  }

  @Test("addTag(to episode) throws on duplicate and removeTag(from episode) unassigns")
  func assignAndUnassignEpisodeTags() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [try Create.unsavedEpisode()]
      )
    )
    let episode = series.episodes[0]

    let tag = try await repo.insertTag(named: "Favorite")
    try await repo.addTag(tag.id, to: episode.id)

    await #expect(throws: DatabaseError.self) {
      try await self.repo.addTag(tag.id, to: episode.id)
    }

    let firstRemove = try await repo.removeTag(tag.id, from: episode.id)
    #expect(firstRemove)

    let secondRemove = try await repo.removeTag(tag.id, from: episode.id)
    #expect(!secondRemove)
  }

  @Test("deleteTag() cascades through episodeTag mappings")
  func deletingTagRemovesEpisodeMappings() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [try Create.unsavedEpisode()]
      )
    )
    let episode = series.episodes[0]

    let tag = try await repo.insertTag(named: "Bookmark")
    try await repo.addTag(tag.id, to: episode.id)

    let removeBeforeDelete = try await repo.removeTag(tag.id, from: episode.id)
    #expect(removeBeforeDelete)

    try await repo.addTag(tag.id, to: episode.id)
    let deleted = try await repo.deleteTag(tag.id)
    #expect(deleted)

    let removeAfterDelete = try await repo.removeTag(tag.id, from: episode.id)
    #expect(!removeAfterDelete)
  }
}
