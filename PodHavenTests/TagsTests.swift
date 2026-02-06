// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of Tag model and repo tests", .container)
class TagsTests {
  @DynamicInjected(\.repo) private var repo

  @Test("insertTag() trims and throws on case-insensitive duplicates")
  func insertTagThrowsOnDuplicate() async throws {
    _ = try await repo.insertTag(named: "  Swift  ")

    await #expect(throws: DatabaseError.self) {
      _ = try await self.repo.insertTag(named: "swift")
    }

    let tags = try await repo.allTags()
    #expect(tags.map(\.name) == ["Swift"])
  }

  @Test("allTags() returns tags ordered by case-insensitive name")
  func allTagsReturnsOrdered() async throws {
    _ = try await repo.insertTag(named: "zeta")
    _ = try await repo.insertTag(named: "Alpha")
    _ = try await repo.insertTag(named: "beta")

    let tags = try await repo.allTags()
    #expect(tags.map(\.name) == ["Alpha", "beta", "zeta"])
  }

  @Test("addTag() throws on duplicate and removeTag() unassigns")
  func assignAndUnassignTags() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: try Create.unsavedPodcast())
    )
    let tag = try await repo.insertTag(named: "Tech")

    let firstAdd = try await repo.addTag(tag.id, to: series.id)
    #expect(firstAdd)

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
    #expect(try await repo.allTags().isEmpty)
  }
}
