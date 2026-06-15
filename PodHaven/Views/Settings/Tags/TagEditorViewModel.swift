// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import IdentifiedCollections
import Logging
import SwiftUI

@Observable @MainActor
class TagEditorViewModel {
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.repo) private var repo
  @ObservationIgnored @DynamicInjected(\.sharedState) private var sharedState
  @ObservationIgnored @DynamicInjected(\.sheet) private var sheet

  private static let log = Log.as(LogSubsystem.SettingsView.tags)

  let tagID: Tag.ID
  var name: String
  var icon: LucideIcon

  init(tag: Tag) {
    self.tagID = tag.id
    self.name = tag.name
    self.icon = tag.icon
  }

  // MARK: - Validation

  // Latches on save so a double-tap can't fire a second write; a successful
  // save dismisses the sheet, so only failure resets to idle.
  enum SaveState: Equatable {
    case idle
    case saving
  }

  private(set) var saveState: SaveState = .idle

  private var trimmedName: String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var canSave: Bool {
    saveState == .idle && !trimmedName.isEmpty
  }

  // MARK: - Persistence

  func save() {
    guard saveState == .idle, !trimmedName.isEmpty else { return }

    if let conflict = sharedState.tags.first(
      where: { $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }
    ),
      conflict.id != tagID
    {
      alert("A tag named \"\(conflict.name)\" already exists.")
      return
    }

    saveState = .saving
    Task { [weak self] in
      guard let self else { return }
      do {
        try await repo.updateTag(tagID, name: trimmedName, icon: icon)
        sheet.dismiss()
      } catch {
        saveState = .idle
        Self.log.caughtError("save: failed to update tag \(tagID)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }
}
