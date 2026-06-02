// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Observation
import Testing

@testable import PodHaven

@Suite("of EpisodeSwipeSettingsViewModel tests", .container)
@MainActor final class EpisodeSwipeSettingsViewModelTests {
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.sharedState) private var sharedState

  private typealias Action = UserSettings.EpisodeSwipeAction

  @Test("defaults to Play/Pause then Rate")
  func defaultsToPlayPauseThenRate() {
    let viewModel = EpisodeSwipeSettingsViewModel()
    #expect(viewModel.actions == [.playPause, .rate])
  }

  @Test("add appends a new action and persists it")
  func addAppendsAndPersists() {
    let viewModel = EpisodeSwipeSettingsViewModel()

    viewModel.add(.cache)

    #expect(viewModel.actions == [.playPause, .rate, .cache])
    let stored = [Action]
      .load(
        from: Container.shared.standardDefaults(),
        forKey: "episodeSwipeActions"
      )
    #expect(stored == [.playPause, .rate, .cache])
  }

  @Test("add ignores a duplicate action")
  func addIgnoresDuplicate() {
    let viewModel = EpisodeSwipeSettingsViewModel()

    viewModel.add(.rate)

    #expect(viewModel.actions == [.playPause, .rate])
  }

  @Test("add stops at the maximum of three actions")
  func addStopsAtMaximum() {
    let viewModel = EpisodeSwipeSettingsViewModel()

    viewModel.add(.cache)
    viewModel.add(.markFinished)
    #expect(viewModel.actions.count == EpisodeSwipeSettingsViewModel.maxActions)

    viewModel.add(.tag)

    #expect(viewModel.actions == [.playPause, .rate, .cache])
  }

  @Test("add ignores Tag when no tags exist")
  func addIgnoresTagWithoutTags() {
    let viewModel = EpisodeSwipeSettingsViewModel()

    viewModel.add(.tag)

    #expect(viewModel.actions == [.playPause, .rate])
  }

  @Test("add appends Tag once a tag exists")
  func addAppendsTagWithTag() async throws {
    let viewModel = EpisodeSwipeSettingsViewModel()

    let tag = try await repo.insertTag(UnsavedTag(name: "Listen Later"))
    sharedState.setTags([tag])

    viewModel.add(.tag)

    #expect(viewModel.actions == [.playPause, .rate, .tag])
  }

  @Test("delete removes an action but always keeps at least one")
  func deleteKeepsAtLeastOne() {
    let viewModel = EpisodeSwipeSettingsViewModel()

    viewModel.delete(at: IndexSet(integer: 1))
    #expect(viewModel.actions == [.playPause])

    viewModel.delete(at: IndexSet(integer: 0))
    #expect(viewModel.actions == [.playPause])
  }

  @Test("move reorders the actions")
  func moveReorders() {
    let viewModel = EpisodeSwipeSettingsViewModel()

    viewModel.move(from: IndexSet(integer: 0), to: 2)

    #expect(viewModel.actions == [.rate, .playPause])
  }

  // SwiftUI's List reorder/delete edits require the bound collection to update
  // within the gesture transaction. A computed pass-through to userSettings
  // notified observers a turn late and scrambled in-flight edits; mutations
  // must wake observers synchronously.
  @Test("mutations notify observers synchronously")
  func mutationsNotifySynchronously() {
    let viewModel = EpisodeSwipeSettingsViewModel()

    let notified = ThreadSafe(false)
    withObservationTracking {
      _ = viewModel.actions
    } onChange: {
      notified(true)
    }

    viewModel.move(from: IndexSet(integer: 0), to: 2)

    #expect(notified())
  }

  @Test("addableActions excludes already-selected actions")
  func addableExcludesSelected() {
    let viewModel = EpisodeSwipeSettingsViewModel()

    #expect(!viewModel.addableActions.contains(.playPause))
    #expect(!viewModel.addableActions.contains(.rate))
    #expect(viewModel.addableActions.contains(.cache))
    #expect(viewModel.addableActions.contains(.saveInCache))
    #expect(viewModel.addableActions.contains(.markFinished))
  }

  @Test("addableActions is empty once the maximum is selected")
  func addableEmptyAtMaximum() {
    let viewModel = EpisodeSwipeSettingsViewModel()

    viewModel.add(.cache)

    #expect(viewModel.actions.count == EpisodeSwipeSettingsViewModel.maxActions)
    #expect(viewModel.addableActions.isEmpty)
  }

  @Test("addableActions hides Tag until a tag exists")
  func tagHiddenUntilTagExists() async throws {
    let viewModel = EpisodeSwipeSettingsViewModel()
    #expect(!viewModel.addableActions.contains(.tag))

    let tag = try await repo.insertTag(UnsavedTag(name: "Listen Later"))
    sharedState.setTags([tag])

    #expect(viewModel.addableActions.contains(.tag))
  }
}
