// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
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
  @Test("the v52 migration seeds decode to the expected default filters")
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
      UnsavedSmartList(title: "Loved", filter: filter, displayOrder: 0)
    )
    #expect(inserted.title == "Loved")
    #expect(inserted.filter == filter)
    #expect(inserted.sortMethod == .newestFirst)

    #expect(try await smartListRepo.fetchAll().map(\.id) == [inserted.id])
    #expect(try await smartListRepo.fetchOne(inserted.id)?.filter == filter)

    #expect(try await smartListRepo.updateTitle(inserted.id, to: "Favorites"))
    let newFilter = SmartListFilter(combinator: .any, conditions: [.state(.isLiked)])
    #expect(try await smartListRepo.updateFilter(inserted.id, to: newFilter))
    #expect(try await smartListRepo.updateSortMethod(inserted.id, to: .longest))

    let updated = try #require(try await smartListRepo.fetchOne(inserted.id))
    #expect(updated.title == "Favorites")
    #expect(updated.filter == newFilter)
    #expect(updated.sortMethod == .longest)

    #expect(try await smartListRepo.delete(inserted.id))
    #expect(try await smartListRepo.fetchOne(inserted.id) == nil)
    #expect(try await smartListRepo.fetchAll().isEmpty)
  }

  // MARK: - Reorder

  @Test("moveSmartList renumbers displayOrder into a dense sequence")
  func reorder() async throws {
    try await clearAll()

    var ids: [SmartList.ID] = []
    for index in 0..<5 {
      let list = try await smartListRepo.insert(
        UnsavedSmartList(title: "L\(index)", filter: SmartListFilter(), displayOrder: index)
      )
      ids.append(list.id)
    }

    // [0,1,2,3,4] -> move 0 to position 3 -> [1,2,3,0,4]
    try await smartListRepo.moveSmartList(ids[0], to: 3)
    // -> move 4 to position 1 -> [1,4,2,3,0]
    try await smartListRepo.moveSmartList(ids[4], to: 1)

    let ordered = try await smartListRepo.fetchAll().map(\.id)
    #expect(ordered == [ids[1], ids[4], ids[2], ids[3], ids[0]])
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
      UnsavedSmartList(title: "A", filter: SmartListFilter(), displayOrder: 0)
    )
    try await count.wait(for: 2)  // after insert
    _ = try await smartListRepo.updateTitle(list.id, to: "B")
    try await count.wait(for: 3)  // after update
  }

  @Test("smartList(id:) reflects updates and becomes nil after delete")
  func smartListByIDObservation() async throws {
    try await clearAll()

    let list = try await smartListRepo.insert(
      UnsavedSmartList(title: "A", filter: SmartListFilter(), displayOrder: 0)
    )
    #expect(try await observatory.smartList(list.id).get()?.title == "A")

    _ = try await smartListRepo.updateTitle(list.id, to: "B")
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
      UnsavedSmartList(
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
    // Nested group consisting solely of the doomed tag is dropped.
    let nested = try await smartListRepo.insert(
      UnsavedSmartList(
        title: "Nested",
        filter: SmartListFilter(
          combinator: .all,
          conditions: [.state(.isFinished)],
          nested: SmartListFilter.Group(
            combinator: .any,
            conditions: [.episodeTag(.hasTag(doomed.id))]
          )
        ),
        displayOrder: 1
      )
    )
    // Top group consisting solely of the doomed tag falls back to match-all.
    let solo = try await smartListRepo.insert(
      UnsavedSmartList(
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
      UnsavedSmartList(title: "Keep", filter: keepFilter, displayOrder: 3)
    )

    #expect(try await repo.deleteTag(doomed.id))

    #expect(
      try #require(try await smartListRepo.fetchOne(mixed.id)).filter
        == SmartListFilter(combinator: .all, conditions: [.state(.isLoved)])
    )
    #expect(
      try #require(try await smartListRepo.fetchOne(nested.id)).filter
        == SmartListFilter(combinator: .all, conditions: [.state(.isFinished)], nested: nil)
    )
    #expect(
      try #require(try await smartListRepo.fetchOne(solo.id)).filter
        == SmartListFilter(combinator: .all, conditions: [])
    )
    #expect(try #require(try await smartListRepo.fetchOne(keep.id)).filter == keepFilter)
  }
}
