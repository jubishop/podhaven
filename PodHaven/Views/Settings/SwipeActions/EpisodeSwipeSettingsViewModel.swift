// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import SwiftUI

@Observable @MainActor final class EpisodeSwipeSettingsViewModel {
  @ObservationIgnored @DynamicInjected(\.sharedState) private var sharedState
  @ObservationIgnored @DynamicInjected(\.userSettings) private var userSettings

  static let maxActions = 3

  var actions: [UserSettings.EpisodeSwipeAction] {
    userSettings.episodeSwipeActions
  }

  // Actions not yet selected, gating "Tag" on at least one tag existing.
  // Empty once the maximum is reached.
  var addableActions: [UserSettings.EpisodeSwipeAction] {
    guard actions.count < Self.maxActions else { return [] }

    let selected = Set(actions)
    return UserSettings.EpisodeSwipeAction.allCases.filter { action in
      guard !selected.contains(action) else { return false }
      if action == .tag { return !sharedState.tags.isEmpty }
      return true
    }
  }

  func add(_ action: UserSettings.EpisodeSwipeAction) {
    guard actions.count < Self.maxActions, !actions.contains(action) else { return }
    if action == .tag, sharedState.tags.isEmpty { return }
    userSettings.$episodeSwipeActions.new(actions + [action])
  }

  func move(from source: IndexSet, to destination: Int) {
    var updated = actions
    updated.move(fromOffsets: source, toOffset: destination)
    userSettings.$episodeSwipeActions.new(updated)
  }

  // Keeps at least one action; an empty delete request is ignored.
  func delete(at offsets: IndexSet) {
    var updated = actions
    updated.remove(atOffsets: offsets)
    guard !updated.isEmpty else { return }
    userSettings.$episodeSwipeActions.new(updated)
  }
}
