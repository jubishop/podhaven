// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Logging
import SwiftUI

@Observable @MainActor
class SmartListEditorViewModel {
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.sheet) private var sheet
  @ObservationIgnored @DynamicInjected(\.smartListRepo) private var smartListRepo

  private static let log = Log.as(LogSubsystem.EpisodesView.smartListEditor)

  enum Mode: Hashable {
    case create
    case edit(SmartList.ID)
  }

  let mode: Mode
  var title: String
  var topGroup: EditableGroup
  var groups: [EditableGroup]
  var alwaysShowPodcastImage: Bool

  init(
    mode: Mode = .create,
    title: String = "",
    filter: SmartListFilter = SmartListFilter(),
    alwaysShowPodcastImage: Bool = false
  ) {
    self.mode = mode
    self.title = title
    self.topGroup = EditableGroup(
      combinator: filter.combinator,
      conditions: filter.conditions.map(EditableCondition.init)
    )
    self.groups = filter.groups.map(EditableGroup.init)
    self.alwaysShowPodcastImage = alwaysShowPodcastImage
  }

  // MARK: - Validation

  // Latches on save so a double-tap can't fire a second write; a successful
  // save dismisses the sheet, so only failure resets to idle.
  enum SaveState: Equatable {
    case idle
    case saving
  }

  private(set) var saveState: SaveState = .idle

  var canSave: Bool {
    saveState == .idle && !trimmedTitle.isEmpty && composedFilter != nil
  }

  // First incomplete row's message; nil when every row composes.
  var validationMessage: String? {
    for condition in allConditions {
      if let message = condition.validationMessage { return message }
    }
    return nil
  }

  // The saved list matches every episode when no conditions are configured.
  var matchesAllEpisodes: Bool {
    allConditions.isEmpty
  }

  private var trimmedTitle: String {
    title.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var allConditions: [EditableCondition] {
    topGroup.conditions + groups.flatMap(\.conditions)
  }

  // nil while any row is incomplete. Empty nested groups are dropped rather
  // than persisted.
  private var composedFilter: SmartListFilter? {
    var conditions: [SmartListFilter.Condition] = []
    for editable in topGroup.conditions {
      guard let condition = editable.condition else { return nil }
      conditions.append(condition)
    }

    var composedGroups: [SmartListFilter.Group] = []
    for group in groups where !group.conditions.isEmpty {
      var groupConditions: [SmartListFilter.Condition] = []
      for editable in group.conditions {
        guard let condition = editable.condition else { return nil }
        groupConditions.append(condition)
      }
      composedGroups.append(
        SmartListFilter.Group(combinator: group.combinator, conditions: groupConditions)
      )
    }

    return SmartListFilter(
      combinator: topGroup.combinator,
      conditions: conditions,
      groups: composedGroups
    )
  }

  // MARK: - Top Group

  func addTopCondition() {
    topGroup.conditions.append(EditableCondition())
  }

  func removeTopCondition(_ id: EditableCondition.ID) {
    topGroup.conditions.removeAll { $0.id == id }
  }

  // MARK: - Nested Groups

  func addGroup() {
    groups.append(EditableGroup(combinator: topGroup.combinator == .all ? .any : .all))
  }

  func removeGroup(_ id: EditableGroup.ID) {
    groups.removeAll { $0.id == id }
  }

  // MARK: - Persistence

  func save() {
    guard saveState == .idle, !trimmedTitle.isEmpty, let filter = composedFilter else { return }
    saveState = .saving
    Task { [weak self] in
      guard let self else { return }
      do {
        switch mode {
        case .create:
          let maxDisplayOrder = try await smartListRepo.fetchAll().map(\.displayOrder).max()
          _ = try await smartListRepo.insert(
            try UnsavedSmartList(
              title: trimmedTitle,
              filter: filter,
              displayOrder: (maxDisplayOrder ?? -1) + 1,
              alwaysShowPodcastImage: alwaysShowPodcastImage
            )
          )
        case .edit(let id):
          try await smartListRepo.update(
            id,
            title: trimmedTitle,
            filter: filter,
            alwaysShowPodcastImage: alwaysShowPodcastImage
          )
        }
        sheet.dismiss()
      } catch {
        saveState = .idle
        Self.log.caughtError("save: failed for '\(trimmedTitle)'", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  func delete() {
    guard case .edit(let id) = mode else { return }
    Task { [weak self] in
      guard let self else { return }
      do {
        try await smartListRepo.delete(id)
        sheet.dismiss()
      } catch {
        Self.log.caughtError("delete: failed for smart list \(id)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }
}
