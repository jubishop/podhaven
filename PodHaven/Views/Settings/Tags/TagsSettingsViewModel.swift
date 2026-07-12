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
  var episodeCounts: [Tag.ID: Int] = [:]

  // MARK: - Initialization

  func execute() async {
    await withDiscardingTaskGroup { group in
      group.addTask { [weak self] in
        guard let self else { return }
        await observePodcastCounts()
      }
      group.addTask { [weak self] in
        guard let self else { return }
        await observeEpisodeCounts()
      }
    }
  }

  private func observePodcastCounts() async {
    do {
      for try await counts in observatory.podcastCountsByTag() {
        guard !Task.isCancelled else { return }
        podcastCounts = counts
      }
    } catch {
      Self.log.caughtError("observePodcastCounts: observation failed", error)
    }
  }

  private func observeEpisodeCounts() async {
    do {
      for try await counts in observatory.episodeCountsByTag() {
        guard !Task.isCancelled else { return }
        episodeCounts = counts
      }
    } catch {
      Self.log.caughtError("observeEpisodeCounts: observation failed", error)
    }
  }

  // MARK: - Actions

  func deleteTag(_ tagID: Tag.ID) {
    let tagName = tags[id: tagID]?.name ?? "this tag"
    let podcastCount = podcastCounts[tagID] ?? 0
    let episodeCount = episodeCounts[tagID] ?? 0
    let message: String =
      if podcastCount > 0 || episodeCount > 0 {
        """
        \"\(tagName)\" is used by \
        \(TagUsageMessage.usage(podcasts: podcastCount, episodes: episodeCount)). \
        Are you sure you want to delete it?
        """
      } else {
        "Are you sure you want to delete \"\(tagName)\"?"
      }

    alert(
      title: "Delete Tag?",
      message
    ) { [weak self] in
      Button("Delete", role: .destructive) {
        guard let self else { return }
        self.performDeleteTag(tagID)
      }
      Button("Cancel", role: .cancel) {}
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
