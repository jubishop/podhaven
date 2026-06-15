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

  enum Mode: Hashable {
    case create
    case edit(Tag.ID)
  }

  let mode: Mode
  var name: String
  var icon: LucideIcon

  private let podcastCount: Int
  private let episodeCount: Int

  init(
    mode: Mode = .create,
    name: String = "",
    icon: LucideIcon = .tag,
    podcastCount: Int = 0,
    episodeCount: Int = 0
  ) {
    self.mode = mode
    self.name = name
    self.icon = icon
    self.podcastCount = podcastCount
    self.episodeCount = episodeCount
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

    let editingID: Tag.ID? =
      switch mode {
      case .create: nil
      case .edit(let id): id
      }
    if let conflict = sharedState.tags.first(
      where: { $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }
    ),
      conflict.id != editingID
    {
      alert("A tag named \"\(conflict.name)\" already exists.")
      return
    }

    saveState = .saving
    Task { [weak self] in
      guard let self else { return }
      do {
        switch mode {
        case .create:
          try await repo.insertTag(UnsavedTag(name: trimmedName, icon: icon))
        case .edit(let id):
          try await repo.updateTag(id, name: trimmedName, icon: icon)
        }
        sheet.dismiss()
      } catch {
        saveState = .idle
        Self.log.caughtError("save: failed to save tag '\(trimmedName)'", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  func deleteTag() {
    guard case .edit(let id) = mode else { return }

    let message: String =
      if podcastCount > 0 || episodeCount > 0 {
        """
        \"\(name)\" is used by \
        \(TagUsageMessage.usage(podcasts: podcastCount, episodes: episodeCount)). \
        Are you sure you want to delete it?
        """
      } else {
        "Are you sure you want to delete \"\(name)\"?"
      }

    alert(title: "Delete Tag?", message) { [weak self] in
      Button("Delete", role: .destructive) {
        guard let self else { return }
        self.performDelete(id)
      }
      Button("Cancel", role: .cancel) {}
    }
  }

  private func performDelete(_ tagID: Tag.ID) {
    Task { [weak self] in
      guard let self else { return }
      do {
        try await repo.deleteTag(tagID)
        sheet.dismiss()
      } catch {
        Self.log.caughtError("deleteTag: failed to delete tag \(tagID)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }
}
