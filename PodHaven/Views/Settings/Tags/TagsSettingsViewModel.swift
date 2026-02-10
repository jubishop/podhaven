// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import IdentifiedCollections
import Logging

@Observable @MainActor class TagsSettingsViewModel {
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.repo) private var repo

  private static let log = Log.as(LogSubsystem.SettingsView.tags)

  // MARK: - State

  var tags: IdentifiedArrayOf<Tag> = []
  var newTagName: String = ""
  var editingTagID: Tag.ID?
  var editingTagName: String = ""

  // MARK: - Actions

  func loadTags() {
    Task { [weak self] in
      guard let self else { return }

      do {
        tags = try await repo.allTags()
      } catch {
        Self.log.error(error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.coreMessage(for: error))
      }
    }
  }

  func addTag() {
    let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return }

    if tags.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
      alert("A tag named \"\(name)\" already exists.")
      return
    }

    Task { [weak self] in
      guard let self else { return }

      do {
        try await repo.insertTag(named: name)
        newTagName = ""
        tags = try await repo.allTags()
      } catch {
        Self.log.error(error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.coreMessage(for: error))
      }
    }
  }

  func startEditing(_ tag: Tag) {
    editingTagID = tag.id
    editingTagName = tag.name
  }

  func cancelEditing() {
    editingTagID = nil
    editingTagName = ""
  }

  func renameTag() {
    guard let tagID = editingTagID else { return }
    let newName = editingTagName.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !newName.isEmpty else {
      cancelEditing()
      return
    }

    // Allow if unchanged
    if let existing = tags[id: tagID], existing.name == newName {
      cancelEditing()
      return
    }

    // Block if another tag has the same name (case-insensitive)
    if let conflict = tags.first(where: { $0.name.caseInsensitiveCompare(newName) == .orderedSame }
    ),
      conflict.id != tagID
    {
      alert("A tag named \"\(conflict.name)\" already exists.")
      return
    }

    Task { [weak self] in
      guard let self else { return }

      do {
        try await repo.renameTag(tagID, newName: newName)
        editingTagID = nil
        editingTagName = ""
        tags = try await repo.allTags()
      } catch {
        Self.log.error(error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.coreMessage(for: error))
      }
    }
  }

  func deleteTag(_ tagID: Tag.ID) {
    Task { [weak self] in
      guard let self else { return }

      do {
        try await repo.deleteTag(tagID)
        tags = try await repo.allTags()
      } catch {
        Self.log.error(error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.coreMessage(for: error))
      }
    }
  }
}
