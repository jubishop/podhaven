// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of Observatory smart-list unread-count tests", .container)
actor SmartListUnreadCountsTests {
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.smartListRepo) private var smartListRepo

  // The migrated test DB ships the 10 seeded lists; clear them for a clean slate.
  private func clearLists() async throws {
    for list in try await smartListRepo.fetchAll() {
      _ = try await smartListRepo.delete(list.id)
    }
  }

  // Insert `count` fresh episodes (one new podcast) so each gets a higher id.
  private func addEpisodes(_ count: Int, finished: Bool = false) async throws {
    _ = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: try (0..<count)
          .map { _ in
            try Create.unsavedEpisode(finishDate: finished ? Date() : nil)
          }
      )
    )
  }

  private func unread(_ id: SmartList.ID) async throws -> Int {
    try await observatory.smartListUnreadCounts().get()[id] ?? 0
  }

  @Test("unread count tracks newly-added matching episodes and clears on markSeen")
  func tracksNewMatchesAndClears() async throws {
    try await clearLists()
    try await addEpisodes(2)

    // Created after two episodes exist, so they read as already seen.
    let list = try await smartListRepo.insert(
      try UnsavedSmartList(title: "All", filter: SmartListFilter(), displayOrder: 0)
    )
    #expect(try await unread(list.id) == 0)

    try await addEpisodes(3)
    #expect(try await unread(list.id) == 3)

    try await smartListRepo.markSeen(list.id)
    #expect(try await unread(list.id) == 0)
  }

  @Test("only episodes matching the filter count toward the badge")
  func onlyMatchingCounts() async throws {
    try await clearLists()
    try await addEpisodes(1)  // baseline so the new list's watermark is set

    let finishedList = try await smartListRepo.insert(
      try UnsavedSmartList(
        title: "Finished",
        filter: SmartListFilter(combinator: .all, conditions: [.state(.isFinished)]),
        displayOrder: 0
      )
    )
    #expect(try await unread(finishedList.id) == 0)

    try await addEpisodes(2, finished: false)  // newer but non-matching
    #expect(try await unread(finishedList.id) == 0)

    try await addEpisodes(3, finished: true)  // newer and matching
    #expect(try await unread(finishedList.id) == 3)
  }

  @Test("a list created against an empty library counts all later matching episodes")
  func nilWatermarkCountsAll() async throws {
    try await clearLists()

    // No episodes yet → the list's watermark is nil (the fresh-install case).
    let list = try await smartListRepo.insert(
      try UnsavedSmartList(title: "All", filter: SmartListFilter(), displayOrder: 0)
    )
    #expect(try await unread(list.id) == 0)

    try await addEpisodes(4)
    #expect(try await unread(list.id) == 4)
  }

  @Test("each list tracks its own watermark independently")
  func independentLists() async throws {
    try await clearLists()
    try await addEpisodes(1)

    let a = try await smartListRepo.insert(
      try UnsavedSmartList(title: "A", filter: SmartListFilter(), displayOrder: 0)
    )
    let b = try await smartListRepo.insert(
      try UnsavedSmartList(title: "B", filter: SmartListFilter(), displayOrder: 1)
    )

    try await addEpisodes(2)
    #expect(try await unread(a.id) == 2)
    #expect(try await unread(b.id) == 2)

    try await smartListRepo.markSeen(a.id)
    #expect(try await unread(a.id) == 0)
    #expect(try await unread(b.id) == 2)
  }
}
