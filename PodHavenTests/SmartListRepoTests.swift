// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of SmartListRepo tests", .container)
class SmartListRepoTests {
  @DynamicInjected(\.smartListRepo) private var smartListRepo
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.repo) private var repo

  // The migrated test DB ships the 10 seeded lists; clear them for a clean slate.
  private func clearAll() async throws {
    for list in try await smartListRepo.fetchAll() {
      _ = try await smartListRepo.delete(list.id)
    }
  }

  // MARK: - Seeded Defaults

  // Locks the migration's hand-spelled filter JSON literals to the model: every
  // seeded row must decode through the SmartList read path into the intended
  // filter, catching a semantic typo that json_valid + a shape check would miss.
  @Test("the v54 migration seeds decode to the expected default filters")
  func seededDefaultsDecode() async throws {
    let expected: [(title: String, filter: SmartListFilter)] = [
      ("Recent Episodes", SmartListFilter()),
      (
        "Unqueued",
        SmartListFilter(combinator: .all, conditions: [.state(.isUnqueued), .state(.isUnfinished)])
      ),
      ("Cached", SmartListFilter(combinator: .all, conditions: [.state(.isCached)])),
      ("Saved", SmartListFilter(combinator: .all, conditions: [.state(.isSaved)])),
      ("Finished", SmartListFilter(combinator: .all, conditions: [.state(.isFinished)])),
      (
        "Unfinished",
        SmartListFilter(combinator: .all, conditions: [.state(.isUnfinished), .state(.isStarted)])
      ),
      (
        "Previously Queued",
        SmartListFilter(combinator: .all, conditions: [.state(.wasPreviouslyQueued)])
      ),
      (
        "Liked",
        SmartListFilter(combinator: .any, conditions: [.state(.isLiked), .state(.isLoved)])
      ),
      ("Disliked", SmartListFilter(combinator: .all, conditions: [.state(.isDisliked)])),
      ("Not Interested", SmartListFilter(combinator: .all, conditions: [.state(.isNotInterested)])),
    ]

    let seeded = try await smartListRepo.fetchAll()
    #expect(seeded.map(\.title) == expected.map(\.title))
    #expect(seeded.map(\.filter) == expected.map(\.filter))
  }

  // MARK: - CRUD

  @Test("insert, fetch, update, and delete a smart list")
  func crud() async throws {
    try await clearAll()

    let filter = SmartListFilter(combinator: .all, conditions: [.state(.isLoved)])
    let inserted = try await smartListRepo.insert(
      try UnsavedSmartList(title: "Loved", filter: filter, displayOrder: 0)
    )
    #expect(inserted.title == "Loved")
    #expect(inserted.filter == filter)
    #expect(inserted.sortMethod == .newestFirst)

    #expect(try await smartListRepo.fetchAll().map(\.id) == [inserted.id])
    #expect(try await smartListRepo.fetchOne(inserted.id)?.filter == filter)

    #expect(!inserted.alwaysShowPodcastImage)

    let newFilter = SmartListFilter(combinator: .any, conditions: [.state(.isLiked)])
    #expect(
      try await smartListRepo.update(
        inserted.id,
        title: "Favorites",
        filter: newFilter,
        alwaysShowPodcastImage: true
      )
    )
    #expect(try await smartListRepo.updateSortMethod(inserted.id, to: .longest))

    let updated = try #require(try await smartListRepo.fetchOne(inserted.id))
    #expect(updated.title == "Favorites")
    #expect(updated.filter == newFilter)
    #expect(updated.sortMethod == .longest)
    #expect(updated.alwaysShowPodcastImage)

    #expect(try await smartListRepo.delete(inserted.id))
    #expect(try await smartListRepo.fetchOne(inserted.id) == nil)
    #expect(try await smartListRepo.fetchAll().isEmpty)
  }

  @Test("blank titles are rejected and stored titles are trimmed")
  func rejectsBlankTitles() async throws {
    try await clearAll()

    #expect(throws: DatabaseError.self) {
      _ = try UnsavedSmartList(title: "   ", filter: SmartListFilter(), displayOrder: 0)
    }

    let list = try await smartListRepo.insert(
      try UnsavedSmartList(title: "  Valid  ", filter: SmartListFilter(), displayOrder: 0)
    )
    #expect(list.title == "Valid")

    await #expect(throws: DatabaseError.self) {
      try await self.smartListRepo.update(
        list.id,
        title: "   ",
        filter: SmartListFilter(),
        alwaysShowPodcastImage: false
      )
    }
    #expect(try await smartListRepo.fetchOne(list.id)?.title == "Valid")

    #expect(
      try await smartListRepo.update(
        list.id,
        title: "  Renamed  ",
        filter: SmartListFilter(),
        alwaysShowPodcastImage: false
      )
    )
    #expect(try await smartListRepo.fetchOne(list.id)?.title == "Renamed")
  }

  // MARK: - Reorder

  @Test("moveSmartList renumbers displayOrder into a dense sequence")
  func reorder() async throws {
    try await clearAll()

    var ids: [SmartList.ID] = []
    for index in 0..<5 {
      let list = try await smartListRepo.insert(
        try UnsavedSmartList(title: "L\(index)", filter: SmartListFilter(), displayOrder: index)
      )
      ids.append(list.id)
    }

    // SwiftUI reports the destination offset from the original list, matching
    // Queue.insert: a downward move to 3 lands at post-removal index 2.
    // [0,1,2,3,4] -> move 0 to position 3 -> [1,2,0,3,4]
    try await smartListRepo.moveSmartList(ids[0], to: 3)
    // -> move 4 to position 1 -> [1,4,2,0,3]
    try await smartListRepo.moveSmartList(ids[4], to: 1)

    let ordered = try await smartListRepo.fetchAll().map(\.id)
    #expect(ordered == [ids[1], ids[4], ids[2], ids[0], ids[3]])
    // displayOrder is a dense 0-based sequence.
    #expect(try await smartListRepo.fetchAll().map(\.displayOrder) == Array(0..<5))
  }

  // MARK: - Observations

  @Test("smartLists() re-emits on insert and on update")
  func smartListsObservationEmits() async throws {
    try await clearAll()

    let count = Counter()
    let observation = observatory.smartLists()
    Task {
      for try await _ in observation {
        await count.increment()
      }
    }

    try await count.wait(for: 1)  // initial empty snapshot
    let list = try await smartListRepo.insert(
      try UnsavedSmartList(title: "A", filter: SmartListFilter(), displayOrder: 0)
    )
    try await count.wait(for: 2)  // after insert
    _ = try await smartListRepo.update(
      list.id,
      title: "B",
      filter: SmartListFilter(),
      alwaysShowPodcastImage: false
    )
    try await count.wait(for: 3)  // after update
  }

  @Test("smartList(id:) reflects updates and becomes nil after delete")
  func smartListByIDObservation() async throws {
    try await clearAll()

    let list = try await smartListRepo.insert(
      try UnsavedSmartList(title: "A", filter: SmartListFilter(), displayOrder: 0)
    )
    #expect(try await observatory.smartList(list.id).get()?.title == "A")

    _ = try await smartListRepo.update(
      list.id,
      title: "B",
      filter: SmartListFilter(),
      alwaysShowPodcastImage: false
    )
    #expect(try await observatory.smartList(list.id).get()?.title == "B")

    _ = try await smartListRepo.delete(list.id)
    #expect(try await observatory.smartList(list.id).get() == nil)
  }

  // MARK: - Scrub On Tag Delete

  @Test("deleting a tag strips it from every stored filter in the same write")
  func scrubOnTagDelete() async throws {
    try await clearAll()

    let doomed = try await repo.insertTag(UnsavedTag(name: "Doomed"))
    let keeper = try await repo.insertTag(UnsavedTag(name: "Keeper"))

    // Condition removed from a mixed top group.
    let mixed = try await smartListRepo.insert(
      try UnsavedSmartList(
        title: "Mixed",
        filter: SmartListFilter(
          combinator: .all,
          conditions: [
            .state(.isLoved),
            .episodeTag(.hasTag(doomed.id)),
            .podcastTag(.doesNotHaveTag(doomed.id)),
          ]
        ),
        displayOrder: 0
      )
    )
    // A group consisting solely of the doomed tag is dropped; a mixed group is
    // scrubbed in place.
    let grouped = try await smartListRepo.insert(
      try UnsavedSmartList(
        title: "Grouped",
        filter: SmartListFilter(
          combinator: .all,
          conditions: [.state(.isFinished)],
          groups: [
            SmartListFilter.Group(
              combinator: .any,
              conditions: [.episodeTag(.hasTag(doomed.id))]
            ),
            SmartListFilter.Group(
              combinator: .any,
              conditions: [.state(.isLiked), .podcastTag(.hasTag(doomed.id))]
            ),
          ]
        ),
        displayOrder: 1
      )
    )
    // Top group consisting solely of the doomed tag falls back to match-all.
    let solo = try await smartListRepo.insert(
      try UnsavedSmartList(
        title: "Solo",
        filter: SmartListFilter(combinator: .all, conditions: [.episodeTag(.hasTag(doomed.id))]),
        displayOrder: 2
      )
    )
    // References only the keeper tag — untouched.
    let keepFilter = SmartListFilter(
      combinator: .all,
      conditions: [.episodeTag(.hasTag(keeper.id))]
    )
    let keep = try await smartListRepo.insert(
      try UnsavedSmartList(title: "Keep", filter: keepFilter, displayOrder: 3)
    )

    #expect(try await repo.deleteTag(doomed.id))

    #expect(
      try #require(try await smartListRepo.fetchOne(mixed.id)).filter
        == SmartListFilter(combinator: .all, conditions: [.state(.isLoved)])
    )
    #expect(
      try #require(try await smartListRepo.fetchOne(grouped.id)).filter
        == SmartListFilter(
          combinator: .all,
          conditions: [.state(.isFinished)],
          groups: [SmartListFilter.Group(combinator: .any, conditions: [.state(.isLiked)])]
        )
    )
    #expect(
      try #require(try await smartListRepo.fetchOne(solo.id)).filter
        == SmartListFilter(combinator: .all, conditions: [])
    )
    #expect(try #require(try await smartListRepo.fetchOne(keep.id)).filter == keepFilter)
  }

  // MARK: - Unread Watermark

  // Insert `count` fresh episodes (one new podcast) so each gets a higher id.
  private func addEpisodes(_ count: Int) async throws {
    _ = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: try (0..<count).map { _ in try Create.unsavedEpisode() }
      )
    )
  }

  private func currentMaxEpisodeID() async throws -> Episode.ID? {
    try await observatory.episodeIDs(filter: AppDB.noOp).get().max()
  }

  @Test("insert stamps the watermark to the current newest episode id")
  func insertStampsWatermark() async throws {
    try await clearAll()

    // Empty library → no watermark.
    let empty = try await smartListRepo.insert(
      try UnsavedSmartList(title: "Empty", filter: SmartListFilter(), displayOrder: 0)
    )
    #expect(empty.lastSeenEpisodeId == nil)

    try await addEpisodes(2)
    let maxID = try await currentMaxEpisodeID()
    let stamped = try await smartListRepo.insert(
      try UnsavedSmartList(title: "Stamped", filter: SmartListFilter(), displayOrder: 1)
    )
    #expect(stamped.lastSeenEpisodeId == maxID)
  }

  @Test("markSeen advances the watermark to the current newest episode id")
  func markSeenAdvancesWatermark() async throws {
    try await clearAll()
    try await addEpisodes(1)

    let list = try await smartListRepo.insert(
      try UnsavedSmartList(title: "A", filter: SmartListFilter(), displayOrder: 0)
    )
    try await addEpisodes(3)
    let newMax = try await currentMaxEpisodeID()
    #expect(list.lastSeenEpisodeId != newMax)  // newer episodes arrived since insert

    try await smartListRepo.markSeen(list.id)
    #expect(try await smartListRepo.fetchOne(list.id)?.lastSeenEpisodeId == newMax)
  }

  @Test("update resets the watermark only when the filter changes")
  func updateResetsWatermarkOnFilterChange() async throws {
    try await clearAll()
    try await addEpisodes(2)

    let lovedFilter = SmartListFilter(combinator: .all, conditions: [.state(.isLoved)])
    let list = try await smartListRepo.insert(
      try UnsavedSmartList(title: "A", filter: lovedFilter, displayOrder: 0)
    )
    let initial = try #require(list.lastSeenEpisodeId)

    // Move the high-water mark forward with newer episodes.
    try await addEpisodes(3)
    let movedMax = try await currentMaxEpisodeID()
    #expect(movedMax != initial)

    // Same filter (title/artwork-only edit) keeps the watermark.
    #expect(
      try await smartListRepo.update(
        list.id,
        title: "Renamed",
        filter: lovedFilter,
        alwaysShowPodcastImage: true
      )
    )
    #expect(try await smartListRepo.fetchOne(list.id)?.lastSeenEpisodeId == initial)

    // A changed filter resets the watermark to the current newest id.
    #expect(
      try await smartListRepo.update(
        list.id,
        title: "Renamed",
        filter: SmartListFilter(combinator: .all, conditions: [.state(.isLiked)]),
        alwaysShowPodcastImage: true
      )
    )
    #expect(try await smartListRepo.fetchOne(list.id)?.lastSeenEpisodeId == movedMax)
  }
}
