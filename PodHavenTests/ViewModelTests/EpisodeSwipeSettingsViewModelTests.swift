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

  // The first configured action lands at the trailing (right) edge, so the
  // left-to-right preview reverses the configuration order.
  @Test("previewActions reverses the configured order")
  func previewActionsReversesOrder() {
    let viewModel = EpisodeSwipeSettingsViewModel()

    #expect(viewModel.previewActions == [.rate, .playPause])

    viewModel.add(.cache)

    #expect(viewModel.previewActions == [.cache, .rate, .playPause])
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

  // The Add Action entries stay listed at the maximum (the section just
  // disables) so the UI doesn't appear and disappear; canAddMore gates adding.
  @Test("addableActions stays listed at the maximum but canAddMore is false")
  func addableListedButBlockedAtMaximum() {
    let viewModel = EpisodeSwipeSettingsViewModel()
    #expect(viewModel.canAddMore)

    viewModel.add(.cache)

    #expect(viewModel.actions.count == EpisodeSwipeSettingsViewModel.maxActions)
    #expect(!viewModel.canAddMore)
    #expect(viewModel.addableActions.contains(.markFinished))
    #expect(viewModel.addableActions.contains(.saveInCache))
    #expect(!viewModel.addableActions.contains(.cache))
  }

  @Test("addableActions hides Tag until a tag exists")
  func tagHiddenUntilTagExists() async throws {
    let viewModel = EpisodeSwipeSettingsViewModel()
    #expect(!viewModel.addableActions.contains(.tag))

    let tag = try await repo.insertTag(UnsavedTag(name: "Listen Later"))
    sharedState.setTags([tag])

    #expect(viewModel.addableActions.contains(.tag))
  }

  @Test("transcription stays hidden while device support is unknown")
  func transcriptionHiddenWhileSupportUnknown() {
    Container.shared.userSettings().$episodeSwipeActions.new([.playPause, .transcribe])
    let viewModel = EpisodeSwipeSettingsViewModel()

    #expect(viewModel.actions == [.playPause])
    #expect(viewModel.previewActions == [.playPause])
    #expect(!viewModel.addableActions.contains(.transcribe))

    viewModel.add(.transcribe)

    #expect(!viewModel.actions.contains(.transcribe))
  }

  @Test("transcription appears once device support is confirmed")
  func transcriptionAppearsOnceSupportConfirmed() async throws {
    let viewModel = EpisodeSwipeSettingsViewModel()
    let notified = ThreadSafe(false)
    withObservationTracking {
      _ = viewModel.addableActions
    } onChange: {
      notified(true)
    }

    await TranscriptionHelpers.prepareAvailability()

    try await Wait.until(
      { @MainActor in notified() },
      { @MainActor in "Expected availability to notify the swipe settings view model" }
    )
    #expect(viewModel.addableActions.contains(.transcribe))

    viewModel.add(.transcribe)

    #expect(viewModel.actions == [.playPause, .rate, .transcribe])
  }

  @Test("transcription stays hidden when device support is unavailable")
  func transcriptionHiddenWhenSupportUnavailable() async {
    Container.shared.userSettings().$episodeSwipeActions.new([.transcribe])
    let viewModel = EpisodeSwipeSettingsViewModel()

    await TranscriptionHelpers.prepareAvailability(
      modelManager: FakeSpeechModelManager(supportedIdentifiers: [])
    )

    #expect(viewModel.actions == [.playPause])
    #expect(viewModel.previewActions == [.playPause])
    #expect(!viewModel.addableActions.contains(.transcribe))
  }
}
