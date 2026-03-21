// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging
import SwiftUI

@Observable @MainActor class TagsSettingsViewModel {
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory
  @ObservationIgnored @DynamicInjected(\.repo) private var repo
  @ObservationIgnored @DynamicInjected(\.sharedState) private var sharedState

  private static let log = Log.as(LogSubsystem.SettingsView.tags)

  // MARK: - State

  var tags: IdentifiedArrayOf<Tag> { sharedState.tags }
  var podcastCounts: [Tag.ID: Int] = [:]
  var newTagName: String = ""
  var editingTagID: Tag.ID?
  var editingTagName: String = ""

  // MARK: - Initialization

  func execute() async {
    do {
      for try await counts in observatory.podcastCountsByTag() {
        guard !Task.isCancelled else { return }
        podcastCounts = counts
      }
    } catch {
      Self.log.caughtError("execute: podcastCountsByTag observation failed", error)
    }
  }

  // MARK: - Actions

  func addTag() {
    let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return }

    if tags.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
      alert("A tag named \"\(name)\" already exists.")
      newTagName = ""
      return
    }

    Task { [weak self] in
      guard let self else { return }

      do {
        try await repo.insertTag(UnsavedTag(name: name))
        newTagName = ""
      } catch {
        Self.log.caughtError("addTag: failed to insert tag '\(name)'", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
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

    // Nothing to persist — exit editing immediately
    guard !newName.isEmpty, tags[id: tagID]?.name != newName else {
      cancelEditing()
      return
    }

    // Block if another tag has the same name (case-insensitive)
    if let conflict = tags.first(
      where: { $0.name.caseInsensitiveCompare(newName) == .orderedSame }
    ),
      conflict.id != tagID
    {
      alert("A tag named \"\(conflict.name)\" already exists.")
      cancelEditing()
      return
    }

    // Keep editing state visible until async rename completes to avoid flicker
    Task { [weak self] in
      guard let self else { return }

      do {
        try await repo.renameTag(tagID, newName: newName)
      } catch {
        Self.log.caughtError("renameTag: failed to rename tag \(tagID) to '\(newName)'", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
      cancelEditing()
    }
  }

  func deleteTag(_ tagID: Tag.ID) {
    let count = podcastCounts[tagID] ?? 0
    if count > 0 {
      let tagName = tags[id: tagID]?.name ?? "this tag"
      alert(
        title: "Delete Tag?",
        "\"\(tagName)\" is used by \(count) \(count == 1 ? "podcast" : "podcasts"). Are you sure you want to delete it?"
      ) { [weak self] in
        Button("Delete", role: .destructive) { self?.performDeleteTag(tagID) }
        Button("Cancel", role: .cancel) {}
      }
    } else {
      performDeleteTag(tagID)
    }
  }

  // MARK: - Private Helpers

  private func performDeleteTag(_ tagID: Tag.ID) {
    Task { [weak self] in
      guard let self else { return }

      do {
        try await repo.deleteTag(tagID)
      } catch {
        Self.log.caughtError("deleteTag: failed to delete tag \(tagID)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }
}
