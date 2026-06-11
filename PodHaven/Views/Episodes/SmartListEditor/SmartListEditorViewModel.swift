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
  var nested: EditableGroup?

  init(mode: Mode = .create, title: String = "", filter: SmartListFilter = SmartListFilter()) {
    self.mode = mode
    self.title = title
    self.topGroup = EditableGroup(
      combinator: filter.combinator,
      conditions: filter.conditions.map(EditableCondition.init)
    )
    if let nestedGroup = filter.nested {
      self.nested = EditableGroup(nestedGroup)
    }
  }

  // MARK: - Validation

  var canSave: Bool {
    !trimmedTitle.isEmpty && composedFilter != nil
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
    topGroup.conditions + (nested?.conditions ?? [])
  }

  // nil while any row is incomplete. An empty nested group is dropped rather
  // than persisted.
  private var composedFilter: SmartListFilter? {
    var conditions: [SmartListFilter.Condition] = []
    for editable in topGroup.conditions {
      guard let condition = editable.condition else { return nil }
      conditions.append(condition)
    }

    var nestedGroup: SmartListFilter.Group?
    if let nested, !nested.conditions.isEmpty {
      var nestedConditions: [SmartListFilter.Condition] = []
      for editable in nested.conditions {
        guard let condition = editable.condition else { return nil }
        nestedConditions.append(condition)
      }
      nestedGroup = SmartListFilter.Group(
        combinator: nested.combinator,
        conditions: nestedConditions
      )
    }

    return SmartListFilter(
      combinator: topGroup.combinator,
      conditions: conditions,
      nested: nestedGroup
    )
  }

  // MARK: - Nested Group

  func addNestedGroup() {
    guard nested == nil else { return }
    nested = EditableGroup(combinator: topGroup.combinator == .all ? .any : .all)
  }

  func removeNestedGroup() {
    nested = nil
  }

  // MARK: - Persistence

  func save() {
    guard !trimmedTitle.isEmpty, let filter = composedFilter else { return }
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
              displayOrder: (maxDisplayOrder ?? -1) + 1
            )
          )
        case .edit(let id):
          try await smartListRepo.updateTitle(id, to: trimmedTitle)
          try await smartListRepo.updateFilter(id, to: filter)
        }
        sheet.dismiss()
      } catch {
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
