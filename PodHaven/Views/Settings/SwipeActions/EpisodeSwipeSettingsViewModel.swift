// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import SwiftUI

@Observable @MainActor final class EpisodeSwipeSettingsViewModel {
  @ObservationIgnored @DynamicInjected(\.sharedState) private var sharedState
  @ObservationIgnored @DynamicInjected(\.transcriptionAvailability)
  private var transcriptionAvailability
  @ObservationIgnored @DynamicInjected(\.userSettings) private var userSettings

  static let maxActions = 3

  // View-facing projection of the persisted setting. Broadcast notifies
  // main-actor writes synchronously, so reorder/delete edits land within the
  // same gesture transaction instead of a runloop turn later.
  private(set) var actions: [UserSettings.EpisodeSwipeAction] {
    get {
      let actions = userSettings.episodeSwipeActions
      guard !transcriptionAvailability.isAvailable else { return actions }
      let visibleActions = actions.filter { $0 != .transcribe }
      return visibleActions.isEmpty ? [.playPause] : visibleActions
    }
    // Edits arrive in terms of the visible actions, so a hidden Transcribe
    // keeps its place in the persisted setting.
    set {
      var persisted = newValue
      if !transcriptionAvailability.isAvailable,
        let hiddenIndex = userSettings.episodeSwipeActions.firstIndex(of: .transcribe)
      {
        persisted.insert(.transcribe, at: min(hiddenIndex, persisted.count))
      }
      userSettings.$episodeSwipeActions.new(persisted)
    }
  }

  // The configured actions laid out left-to-right as a swipe reveals them.
  // SwiftUI fills trailing-edge swipe actions from the trailing edge inward,
  // so the first configured action is rightmost (and the full-swipe action);
  // reverse to read the row left-to-right for the preview.
  var previewActions: [UserSettings.EpisodeSwipeAction] {
    actions.reversed()
  }

  // Counts a hidden Transcribe, which still occupies a persisted slot.
  var canAddMore: Bool {
    userSettings.episodeSwipeActions.count < Self.maxActions
  }

  // Actions not yet selected, gating "Tag" on at least one tag existing. These
  // stay listed even at the maximum so the section doesn't appear and disappear;
  // canAddMore drives whether they are enabled.
  var addableActions: [UserSettings.EpisodeSwipeAction] {
    let selected = Set(actions)
    return UserSettings.EpisodeSwipeAction.allCases.filter { action in
      guard !selected.contains(action) else { return false }
      if action == .tag { return !sharedState.tags.isEmpty }
      if action == .transcribe { return transcriptionAvailability.isAvailable }
      return true
    }
  }

  func add(_ action: UserSettings.EpisodeSwipeAction) {
    guard canAddMore, !actions.contains(action) else { return }
    if action == .tag, sharedState.tags.isEmpty { return }
    if action == .transcribe, !transcriptionAvailability.isAvailable { return }
    actions.append(action)
  }

  func move(from source: IndexSet, to destination: Int) {
    actions.move(fromOffsets: source, toOffset: destination)
  }

  // Keeps at least one action; an empty delete request is ignored.
  func delete(at offsets: IndexSet) {
    guard !offsets.isEmpty else { return }

    var updated = actions
    updated.remove(atOffsets: offsets)
    guard !updated.isEmpty else { return }
    actions = updated
  }
}
