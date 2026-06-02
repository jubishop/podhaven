// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import SwiftUI

@Observable @MainActor final class EpisodeSwipeSettingsViewModel {
  @ObservationIgnored @DynamicInjected(\.sharedState) private var sharedState
  @ObservationIgnored @DynamicInjected(\.userSettings) private var userSettings

  static let maxActions = 3

  // The List edits this array directly. It is held here and mutated
  // synchronously so SwiftUI's reorder/delete edits land in the same
  // transaction as the gesture. A computed pass-through to userSettings
  // notifies observers a turn late (Broadcast hops to the main actor),
  // which scrambles in-flight List edits. didSet persists every mutation;
  // it does not fire for the init seed below.
  private(set) var actions: [UserSettings.EpisodeSwipeAction] {
    didSet { userSettings.$episodeSwipeActions.new(actions) }
  }

  init() {
    actions = Container.shared.userSettings().episodeSwipeActions
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
    actions.append(action)
  }

  func move(from source: IndexSet, to destination: Int) {
    actions.move(fromOffsets: source, toOffset: destination)
  }

  // Keeps at least one action; an empty delete request is ignored.
  func delete(at offsets: IndexSet) {
    var updated = actions
    updated.remove(atOffsets: offsets)
    guard !updated.isEmpty else { return }
    actions = updated
  }
}
