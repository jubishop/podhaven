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

    let fetched = try await repo.podcastSeriesDetail(series.id)
    #expect(fetched?.tags.map(\.id) == [tag.id])

    let firstRemove = try await repo.removeTag(tag.id, from: series.id)
    let secondRemove = try await repo.removeTag(tag.id, from: series.id)

    #expect(firstRemove)
    #expect(!secondRemove)
    let afterRemove = try await repo.podcastSeriesDetail(series.id)
    #expect(afterRemove?.tags.isEmpty == true)
  }

  @Test("podcastSeriesDetail() includes associated tags")
  func podcastSeriesDetailIncludesTags() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: try Create.unsavedPodcast())
    )

    let tagOne = try await repo.insertTag(UnsavedTag(name: "beta"))
    let tagTwo = try await repo.insertTag(UnsavedTag(name: "Alpha"))

    _ = try await repo.addTag(tagOne.id, to: series.id)
    _ = try await repo.addTag(tagTwo.id, to: series.id)

    let fetched = try await repo.podcastSeriesDetail(series.id)
    #expect(fetched != nil)
    #expect(fetched?.tags.map(\.name) == ["Alpha", "beta"])
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

    let fetched = try await repo.podcastSeriesDetail(series.id)
    #expect(fetched?.tags.map(\.id) == [tag.id])
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

  @Test("observatory.episodeCountsByTag() returns correct counts per tag")
  func episodeCountsByTag() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: "ep-a"),
          try Create.unsavedEpisode(guid: "ep-b"),
        ]
      )
    )
    let episodeIDs = series.episodes.map(\.id)
    let tagOne = try await repo.insertTag(UnsavedTag(name: "Bookmark"))
    let tagTwo = try await repo.insertTag(UnsavedTag(name: "Listen Later"))
    _ = try await repo.insertTag(UnsavedTag(name: "Unattached"))

    try await repo.addTag(tagOne.id, to: episodeIDs[0])
    try await repo.addTag(tagOne.id, to: episodeIDs[1])
    try await repo.addTag(tagTwo.id, to: episodeIDs[0])

    let counts = try await observatory.episodeCountsByTag().get()
    #expect(counts[tagOne.id] == 2)
    #expect(counts[tagTwo.id] == 1)
    #expect(counts.count == 2)
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
    let beforeDelete = try await repo.podcastSeriesDetail(series.id)
    #expect(beforeDelete?.tags.count == 1)

    let deleted = try await repo.deleteTag(tag.id)
    #expect(deleted)
    let afterDelete = try await repo.podcastSeriesDetail(series.id)
    #expect(afterDelete?.tags.isEmpty == true)
    #expect(try await observatory.tags().get().isEmpty)
  }

  @Test("addTag(to episode) throws SQLITE_CONSTRAINT_UNIQUE on duplicate")
  func addTagToEpisodeThrowsUniqueOnDuplicate() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [try Create.unsavedEpisode()]
      )
    )
    let episode = series.episodes[0]

    let tag = try await repo.insertTag(UnsavedTag(name: "Favorite"))
    try await repo.addTag(tag.id, to: episode.id)

    // Pins the error pattern that applyTagToSelectedEpisodes' bulk catch
    // relies on — see SelectableEpisodeList.applyTagToSelectedEpisodes.
    // If GRDB ever stops surfacing this duplicate as
    // DatabaseError.SQLITE_CONSTRAINT_UNIQUE, the production catch
    // silently turns into a generic .error log; this test fails first.
    do {
      try await repo.addTag(tag.id, to: episode.id)
      Issue.record("expected duplicate addTag to throw SQLITE_CONSTRAINT_UNIQUE")
    } catch DatabaseError.SQLITE_CONSTRAINT_UNIQUE {
      // expected
    }

    let firstRemove = try await repo.removeTag(tag.id, from: episode.id)
    #expect(firstRemove)

    let secondRemove = try await repo.removeTag(tag.id, from: episode.id)
    #expect(!secondRemove)
  }

  @Test("observatory.podcastEpisodeWithTags() returns tags ordered by case-insensitive name")
  func observatoryPodcastEpisodeWithTagsReturnsOrderedTags() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [try Create.unsavedEpisode()]
      )
    )
    let episode = series.episodes[0]

    // Names chosen so binary and .nocase orderings diverge: binary sorts to
    // [Apple, Cherry, banana] (uppercase before lowercase), case-insensitive
    // sorts to [Apple, banana, Cherry].
    let banana = try await repo.insertTag(UnsavedTag(name: "banana"))
    let cherry = try await repo.insertTag(UnsavedTag(name: "Cherry"))
    let apple = try await repo.insertTag(UnsavedTag(name: "Apple"))
    _ = try await repo.insertTag(UnsavedTag(name: "Unattached"))

    try await repo.addTag(banana.id, to: episode.id)
    try await repo.addTag(cherry.id, to: episode.id)
    try await repo.addTag(apple.id, to: episode.id)

    let observed = try #require(try await observatory.podcastEpisodeWithTags(episode.id).get())
    #expect(observed.tags.map(\.name) == ["Apple", "banana", "Cherry"])
  }

  @Test("ListablePodcastEpisode.request materialises tagIDs from the episodeTag JOIN")
  func listablePodcastEpisodeMaterialisesTagIDs() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: "tagged"),
          try Create.unsavedEpisode(guid: "untagged"),
        ]
      )
    )
    let tagged = series.episodes[0]
    let untagged = series.episodes[1]

    let tagOne = try await repo.insertTag(UnsavedTag(name: "Alpha"))
    let tagTwo = try await repo.insertTag(UnsavedTag(name: "Beta"))
    _ = try await repo.insertTag(UnsavedTag(name: "Unattached"))

    try await repo.addTag(tagOne.id, to: tagged.id)
    try await repo.addTag(tagTwo.id, to: tagged.id)

    let listables = try await repo.db.read { db in
      try ListablePodcastEpisode
        .request(filter: AppDB.NoOp, order: Episode.Columns.id.asc)
        .fetchAll(db)
    }

    let taggedRow = try #require(listables.first { $0.id == tagged.id })
    let untaggedRow = try #require(listables.first { $0.id == untagged.id })
    #expect(taggedRow.tagIDs == [tagOne.id, tagTwo.id])
    #expect(untaggedRow.tagIDs == [])
  }

  @Test("listablePodcastEpisodes() re-emits when episodeTag rows change")
  func listablePodcastEpisodesEmitsOnTagChange() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [try Create.unsavedEpisode()]
      )
    )
    let episodeID = series.episodes[0].id
    let tag = try await repo.insertTag(UnsavedTag(name: "Bookmark"))

    let updateCount = Counter()
    let observation: AsyncValueObservation<[ListablePodcastEpisode]> =
      observatory.listablePodcastEpisodes(
        filter: Episode.Columns.id == episodeID
      )
    Task {
      for try await _ in observation {
        await updateCount.increment()
      }
    }

    try await updateCount.wait(for: 1)
    try await repo.addTag(tag.id, to: episodeID)
    try await updateCount.wait(for: 2)

    _ = try await repo.removeTag(tag.id, from: episodeID)
    try await updateCount.wait(for: 3)
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
