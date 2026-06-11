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

    viewModel.addNestedGroup()
    var loved = EditableCondition()
    loved.kind = .state
    loved.state = .isLoved
    var liked = EditableCondition()
    liked.kind = .state
    liked.state = .isLiked
    viewModel.nested?.conditions = [loved, liked]

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
          nested: SmartListFilter.Group(
            combinator: .any,
            conditions: [.state(.isLoved), .state(.isLiked)]
          )
        )
    )
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

  @Test("an empty nested group is dropped on save")
  func emptyNestedGroupDroppedOnSave() async throws {
    let existing = try #require(try await smartListRepo.fetchAll().first)
    let viewModel = SmartListEditorViewModel(
      mode: .edit(existing.id),
      title: existing.title,
      filter: existing.filter
    )
    viewModel.addNestedGroup()
    #expect(viewModel.canSave)

    viewModel.save()

    try await Wait.until(
      { @MainActor in try await self.smartListRepo.fetchOne(existing.id)?.filter.nested == nil },
      { "Expected the empty nested group to be dropped" }
    )
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
    viewModel.addNestedGroup()
    var text = EditableCondition()
    text.kind = .podcastDescription
    viewModel.nested?.conditions = [text]
    #expect(!viewModel.canSave)
  }

  @Test("the nested group defaults to the opposite combinator of the top group")
  func nestedGroupDefaultsToOppositeCombinator() {
    let viewModel = SmartListEditorViewModel(mode: .create, title: "Named")
    viewModel.topGroup.combinator = .all
    viewModel.addNestedGroup()
    #expect(viewModel.nested?.combinator == .any)

    viewModel.removeNestedGroup()
    #expect(viewModel.nested == nil)
    viewModel.topGroup.combinator = .any
    viewModel.addNestedGroup()
    #expect(viewModel.nested?.combinator == .all)
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
