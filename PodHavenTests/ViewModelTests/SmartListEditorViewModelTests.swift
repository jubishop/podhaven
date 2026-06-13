// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("of SmartListEditorViewModel tests", .container)
@MainActor final class SmartListEditorViewModelTests {
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.smartListRepo) private var smartListRepo

  // MARK: - Save

  @Test("create mode saves a new list with the composed filter and next displayOrder")
  func createSavesComposedFilter() async throws {
    let viewModel = SmartListEditorViewModel(mode: .create)
    viewModel.title = "  Tech Hits  "

    var text = EditableCondition()
    text.kind = .podcastTitle
    text.textOp = .contains
    text.text = "Tech"
    var duration = EditableCondition()
    duration.kind = .duration
    duration.maxMinutesText = "30"
    viewModel.topGroup.combinator = .all
    viewModel.topGroup.conditions = [text, duration]

    viewModel.addGroup()
    var loved = EditableCondition()
    loved.kind = .state
    loved.state = .isLoved
    var liked = EditableCondition()
    liked.kind = .state
    liked.state = .isLiked
    viewModel.groups[0].conditions = [loved, liked]

    viewModel.addGroup()
    var cached = EditableCondition()
    cached.kind = .state
    cached.state = .isCached
    var savedInCache = EditableCondition()
    savedInCache.kind = .state
    savedInCache.state = .isSaved
    viewModel.groups[1].conditions = [cached, savedInCache]

    #expect(viewModel.canSave)
    viewModel.save()

    try await Wait.until(
      { @MainActor in try await self.smartListRepo.fetchAll().contains { $0.title == "Tech Hits" }
      },
      { "Expected save to insert the new list" }
    )
    let saved = try #require(
      try await smartListRepo.fetchAll().first { $0.title == "Tech Hits" }
    )
    #expect(saved.displayOrder == 10)
    #expect(
      saved.filter
        == SmartListFilter(
          combinator: .all,
          conditions: [
            .podcastText(.title, .contains, "Tech"),
            .duration(minSeconds: nil, maxSeconds: 1800),
          ],
          groups: [
            SmartListFilter.Group(
              combinator: .any,
              conditions: [.state(.isLoved), .state(.isLiked)]
            ),
            SmartListFilter.Group(
              combinator: .any,
              conditions: [.state(.isCached), .state(.isSaved)]
            ),
          ]
        )
    )
  }

  @Test("a second save while the create is in flight cannot insert a duplicate")
  func inFlightSaveBlocksDuplicateCreate() async throws {
    let viewModel = SmartListEditorViewModel(mode: .create, title: "Once")

    #expect(viewModel.canSave)
    viewModel.save()
    #expect(!viewModel.canSave)
    viewModel.save()

    try await Wait.until(
      { @MainActor in try await self.smartListRepo.fetchAll().contains { $0.title == "Once" } },
      { "Expected the first save to insert the list" }
    )
    let count = try await smartListRepo.fetchAll().filter { $0.title == "Once" }.count
    #expect(count == 1)
  }

  @Test("edit mode saves the new title and filter onto the existing row")
  func editSavesTitleAndFilter() async throws {
    let existing = try #require(try await smartListRepo.fetchAll().first)
    let viewModel = SmartListEditorViewModel(
      mode: .edit(existing.id),
      title: existing.title,
      filter: existing.filter
    )

    viewModel.title = "Renamed"
    var condition = EditableCondition()
    condition.kind = .state
    condition.state = .isCached
    viewModel.topGroup.conditions = [condition]

    viewModel.save()

    try await Wait.until(
      { @MainActor in try await self.smartListRepo.fetchOne(existing.id)?.title == "Renamed" },
      { "Expected save to rename the row" }
    )
    let saved = try #require(try await smartListRepo.fetchOne(existing.id))
    #expect(saved.filter.conditions == [.state(.isCached)])
  }

  @Test("the artwork preference is persisted on create and edited onto the row")
  func artworkPreferencePersists() async throws {
    let createVM = SmartListEditorViewModel(mode: .create, title: "Podcast Art")
    createVM.alwaysShowPodcastImage = true
    createVM.save()

    try await Wait.until(
      { @MainActor in try await self.smartListRepo.fetchAll().contains { $0.title == "Podcast Art" }
      },
      { "Expected save to insert the new list" }
    )
    let created = try #require(
      try await smartListRepo.fetchAll().first { $0.title == "Podcast Art" }
    )
    #expect(created.alwaysShowPodcastImage)

    let editVM = SmartListEditorViewModel(
      mode: .edit(created.id),
      title: created.title,
      filter: created.filter,
      alwaysShowPodcastImage: created.alwaysShowPodcastImage
    )
    editVM.alwaysShowPodcastImage = false
    editVM.save()

    try await Wait.until(
      { @MainActor in try await self.smartListRepo.fetchOne(created.id)?.alwaysShowPodcastImage
          == false
      },
      { "Expected the edit to clear the artwork preference" }
    )
  }

  @Test("empty nested groups are dropped on save")
  func emptyGroupsDroppedOnSave() async throws {
    let existing = try #require(try await smartListRepo.fetchAll().first)
    let viewModel = SmartListEditorViewModel(
      mode: .edit(existing.id),
      title: existing.title,
      filter: existing.filter
    )
    // The pre-save row already has no groups, so a groups assertion alone
    // could pass without any write; the title edit proves the save landed.
    viewModel.title = existing.title + " Updated"
    viewModel.addGroup()
    viewModel.addGroup()
    #expect(viewModel.canSave)

    viewModel.save()

    try await Wait.until(
      { @MainActor in
        try await self.smartListRepo.fetchOne(existing.id)?.title == existing.title + " Updated"
      },
      { "Expected save to update the row" }
    )
    let saved = try #require(try await smartListRepo.fetchOne(existing.id))
    #expect(saved.filter.groups.isEmpty)
  }

  @Test("delete removes the row in edit mode")
  func deleteRemovesRow() async throws {
    let existing = try #require(try await smartListRepo.fetchAll().first)
    let viewModel = SmartListEditorViewModel(
      mode: .edit(existing.id),
      title: existing.title,
      filter: existing.filter
    )

    viewModel.delete()

    try await Wait.until(
      { @MainActor in try await self.smartListRepo.fetchOne(existing.id) == nil },
      { "Expected delete to remove the row" }
    )
  }

  // MARK: - Validation

  @Test("canSave requires a non-blank title")
  func canSaveRequiresTitle() {
    let viewModel = SmartListEditorViewModel(mode: .create)
    viewModel.title = "   "
    #expect(!viewModel.canSave)

    viewModel.title = "Named"
    #expect(viewModel.canSave)
  }

  @Test("an empty filter is allowed but flagged as match-all")
  func emptyFilterIsMatchAll() {
    let viewModel = SmartListEditorViewModel(mode: .create, title: "Everything")
    #expect(viewModel.canSave)
    #expect(viewModel.matchesAllEpisodes)
  }

  @Test("incomplete conditions block save with a validation message")
  func incompleteConditionsBlockSave() {
    let viewModel = SmartListEditorViewModel(mode: .create, title: "Named")

    var text = EditableCondition()
    text.kind = .episodeTitle
    viewModel.topGroup.conditions = [text]
    #expect(!viewModel.canSave)
    #expect(viewModel.validationMessage == "Enter text to match")

    var tag = EditableCondition()
    tag.kind = .episodeTag
    tag.tagMembership = .hasTag
    viewModel.topGroup.conditions = [tag]
    #expect(!viewModel.canSave)
    #expect(viewModel.validationMessage == "Select a tag")

    var duration = EditableCondition()
    duration.kind = .duration
    viewModel.topGroup.conditions = [duration]
    #expect(!viewModel.canSave)
    #expect(viewModel.validationMessage == "Enter a minimum or maximum duration")

    duration.minMinutesText = "45"
    duration.maxMinutesText = "30"
    viewModel.topGroup.conditions = [duration]
    #expect(!viewModel.canSave)
    #expect(viewModel.validationMessage == "Minimum duration exceeds maximum")

    duration.minMinutesText = "abc"
    viewModel.topGroup.conditions = [duration]
    #expect(!viewModel.canSave)
    #expect(viewModel.validationMessage == "Durations must be whole minutes")

    var publishDate = EditableCondition()
    publishDate.kind = .publishDate
    viewModel.topGroup.conditions = [publishDate]
    #expect(!viewModel.canSave)
    #expect(viewModel.validationMessage == "Enter a number of days")
  }

  @Test("overflow-magnitude duration minutes are invalid instead of trapping")
  func hugeDurationMinutesAreInvalid() {
    let viewModel = SmartListEditorViewModel(mode: .create, title: "Named")

    // Large enough that converting minutes to seconds would overflow Int.
    var duration = EditableCondition()
    duration.kind = .duration
    duration.minMinutesText = "999999999999999999"
    viewModel.topGroup.conditions = [duration]

    #expect(!viewModel.canSave)
    #expect(viewModel.validationMessage == "Durations must be whole minutes")
  }

  @Test("an incomplete nested condition blocks save")
  func incompleteNestedConditionBlocksSave() {
    let viewModel = SmartListEditorViewModel(mode: .create, title: "Named")
    viewModel.addGroup()
    var text = EditableCondition()
    text.kind = .podcastDescription
    viewModel.groups[0].conditions = [text]
    #expect(!viewModel.canSave)
  }

  @Test("each added group defaults to the opposite combinator of the top group")
  func addedGroupsDefaultToOppositeCombinator() {
    let viewModel = SmartListEditorViewModel(mode: .create, title: "Named")
    viewModel.topGroup.combinator = .all
    viewModel.addGroup()
    viewModel.addGroup()
    #expect(viewModel.groups.map(\.combinator) == [.any, .any])

    viewModel.topGroup.combinator = .any
    viewModel.addGroup()
    #expect(viewModel.groups.map(\.combinator) == [.any, .any, .all])
  }

  @Test("removeGroup removes only the identified group")
  func removeGroupRemovesOnlyThatGroup() {
    let viewModel = SmartListEditorViewModel(mode: .create, title: "Named")
    viewModel.addGroup()
    viewModel.addGroup()
    viewModel.addGroup()
    var condition = EditableCondition()
    condition.kind = .state
    condition.state = .isLoved
    viewModel.groups[2].conditions = [condition]

    viewModel.removeGroup(viewModel.groups[1].id)

    #expect(viewModel.groups.count == 2)
    #expect(viewModel.groups[1].conditions.count == 1)
  }

  // MARK: - EditableCondition Round-Trip

  @Test("every condition kind survives the EditableCondition round-trip")
  func editableConditionRoundTrip() async throws {
    let tag = try await repo.insertTag(UnsavedTag(name: "Loop"))
    let conditions: [SmartListFilter.Condition] = [
      .episodeText(.title, .contains, "AI"),
      .episodeText(.description, .doesNotContain, "ad"),
      .podcastText(.title, .startsWith, "The"),
      .podcastText(.description, .equals, "exact"),
      .state(.wasPreviouslyQueued),
      .episodeTag(.hasTag(tag.id)),
      .episodeTag(.hasNoTags),
      .podcastTag(.doesNotHaveTag(tag.id)),
      .podcastTag(.hasAnyTag),
      .duration(minSeconds: 600, maxSeconds: 3600),
      .duration(minSeconds: nil, maxSeconds: 1800),
      .duration(minSeconds: 600, maxSeconds: nil),
      .publishDate(.withinLast, days: 7),
      .publishDate(.olderThan, days: 30),
    ]
    for condition in conditions {
      #expect(EditableCondition(condition).condition == condition)
    }
  }
}
