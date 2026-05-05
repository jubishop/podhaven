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
    _ = try await repo.insertTag(UnsavedTag(name: "  Swift  "))

    await #expect(throws: DatabaseError.self) {
      _ = try await self.repo.insertTag(UnsavedTag(name: "swift"))
    }

    let tags = try await observatory.tags().get()
    #expect(tags.map(\.name) == ["Swift"])
  }

  @Test("insertTag() throws on empty string")
  func insertTagThrowsOnEmpty() async throws {
    await #expect(throws: DatabaseError.self) {
      _ = try await self.repo.insertTag(UnsavedTag(name: ""))
    }

    await #expect(throws: DatabaseError.self) {
      _ = try await self.repo.insertTag(UnsavedTag(name: "   "))
    }

    let tags = try await observatory.tags().get()
    #expect(tags.isEmpty)
  }

  @Test("observatory.tags() returns tags ordered by case-insensitive name")
  func tagsReturnsOrdered() async throws {
    _ = try await repo.insertTag(UnsavedTag(name: "zeta"))
    _ = try await repo.insertTag(UnsavedTag(name: "Alpha"))
    _ = try await repo.insertTag(UnsavedTag(name: "beta"))

    let tags = try await observatory.tags().get()
    #expect(tags.map(\.name) == ["Alpha", "beta", "zeta"])
  }

  @Test("addTag() throws on duplicate and removeTag() unassigns")
  func assignAndUnassignTags() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: try Create.unsavedPodcast())
    )

    let tag = try await repo.insertTag(UnsavedTag(name: "Tech"))
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

    let tagOne = try await repo.insertTag(UnsavedTag(name: "beta"))
    let tagTwo = try await repo.insertTag(UnsavedTag(name: "Alpha"))

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
    let tag = try await repo.insertTag(UnsavedTag(name: "Tech"))
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
    let tag = try await repo.insertTag(UnsavedTag(name: "news"))
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
    _ = try await repo.insertTag(UnsavedTag(name: "News"))
    let tech = try await repo.insertTag(UnsavedTag(name: "Tech"))

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

    let tagOne = try await repo.insertTag(UnsavedTag(name: "News"))
    let tagTwo = try await repo.insertTag(UnsavedTag(name: "Tech"))
    _ = try await repo.insertTag(UnsavedTag(name: "Empty"))

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
    let tag = try await repo.insertTag(UnsavedTag(name: "News"))

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

    let tag = try await repo.insertTag(UnsavedTag(name: "Favorite"))
    try await repo.addTag(tag.id, to: episode.id)

    await #expect(throws: DatabaseError.self) {
      try await self.repo.addTag(tag.id, to: episode.id)
    }

    let firstRemove = try await repo.removeTag(tag.id, from: episode.id)
    #expect(firstRemove)

    let secondRemove = try await repo.removeTag(tag.id, from: episode.id)
    #expect(!secondRemove)
  }

  @Test("applyTag(to:) is idempotent and returns count of newly inserted rows")
  func applyTagIsIdempotent() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: "ep-a"),
          try Create.unsavedEpisode(guid: "ep-b"),
          try Create.unsavedEpisode(guid: "ep-c"),
        ]
      )
    )
    let episodeIDs = series.episodes.map(\.id)
    let tag = try await repo.insertTag(UnsavedTag(name: "Bulk"))

    try await repo.addTag(tag.id, to: episodeIDs[0])

    let firstApply = try await repo.applyTag(tag.id, to: episodeIDs)
    #expect(firstApply == 2)

    let secondApply = try await repo.applyTag(tag.id, to: episodeIDs)
    #expect(secondApply == 0)

    for episodeID in episodeIDs {
      let tags = try await observatory.episodeTags(episodeID).get()
      #expect(tags.map(\.id) == [tag.id])
    }
  }

  @Test("applyTag(to:) returns zero for an empty episode list")
  func applyTagEmptyList() async throws {
    let tag = try await repo.insertTag(UnsavedTag(name: "Empty"))
    let inserted = try await repo.applyTag(tag.id, to: [])
    #expect(inserted == 0)
  }

  @Test("observatory.episodeTags() returns tags ordered by case-insensitive name")
  func observatoryEpisodeTagsReturnsOrdered() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [try Create.unsavedEpisode()]
      )
    )
    let episode = series.episodes[0]

    let zeta = try await repo.insertTag(UnsavedTag(name: "zeta"))
    let alpha = try await repo.insertTag(UnsavedTag(name: "Alpha"))
    let beta = try await repo.insertTag(UnsavedTag(name: "beta"))
    _ = try await repo.insertTag(UnsavedTag(name: "Unattached"))

    try await repo.addTag(zeta.id, to: episode.id)
    try await repo.addTag(alpha.id, to: episode.id)
    try await repo.addTag(beta.id, to: episode.id)

    let tags = try await observatory.episodeTags(episode.id).get()
    #expect(tags.map(\.name) == ["Alpha", "beta", "zeta"])
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

    let tag = try await repo.insertTag(UnsavedTag(name: "Bookmark"))
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
