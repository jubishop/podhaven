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

  var tags: [Tag] = []
  var newTagName: String = ""

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
