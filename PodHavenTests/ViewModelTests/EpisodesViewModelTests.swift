// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("of EpisodesViewModel tests", .container)
@MainActor final class EpisodesViewModelTests {
  @DynamicInjected(\.smartListRepo) private var smartListRepo

  private func withObservingViewModel<T>(
    _ body: (EpisodesViewModel) async throws -> T
  ) async throws -> T {
    let viewModel = EpisodesViewModel()
    let task = Task { @MainActor in
      await viewModel.observeSmartLists()
    }
    defer { task.cancel() }
    return try await body(viewModel)
  }

  @Test("observeSmartLists loads the seeded lists and reacts to inserts")
  func observesSeededListsAndInserts() async throws {
    try await withObservingViewModel { viewModel in
      try await Wait.until(
        { @MainActor in
          viewModel.loadingState == .loaded && viewModel.smartLists.count == 10
        },
        { @MainActor in
          """
          Expected the 10 seeded lists; got state \(viewModel.loadingState) with \
          \(viewModel.smartLists.count) lists
          """
        }
      )

      _ = try await smartListRepo.insert(
        try UnsavedSmartList(title: "Fresh", filter: SmartListFilter(), displayOrder: 10)
      )

      try await Wait.until(
        { @MainActor in viewModel.smartLists.map(\.title).contains("Fresh") },
        { @MainActor in
          "Expected the insert to appear; got \(viewModel.smartLists.map(\.title))"
        }
      )
    }
  }

  @Test("moveSmartList persists the reorder")
  func moveSmartListPersistsReorder() async throws {
    try await withObservingViewModel { viewModel in
      try await Wait.until(
        { @MainActor in viewModel.smartLists.count == 10 },
        { @MainActor in "Expected the 10 seeded lists; got \(viewModel.smartLists.count)" }
      )

      let originalTitles = viewModel.smartLists.map(\.title)
      // SwiftUI destination offset 3 moves the first row below the next two.
      viewModel.moveSmartList(from: IndexSet(integer: 0), to: 3)

      var expected = originalTitles
      let moved = expected.removeFirst()
      expected.insert(moved, at: 2)

      try await Wait.until(
        { @MainActor in viewModel.smartLists.map(\.title) == expected },
        { @MainActor in
          "Expected \(expected) after the move; got \(viewModel.smartLists.map(\.title))"
        }
      )

      let persisted = try await smartListRepo.fetchAll()
      #expect(persisted.map(\.title) == expected)
      #expect(persisted.map(\.displayOrder) == Array(0..<10))
    }
  }

  @Test("moveSmartList ignores a stale out-of-bounds source index")
  func moveSmartListIgnoresStaleIndex() async throws {
    // No observation started, so the view model still holds an empty array.
    let viewModel = EpisodesViewModel()

    viewModel.moveSmartList(from: IndexSet(integer: 0), to: 1)

    let persisted = try await smartListRepo.fetchAll()
    #expect(persisted.map(\.displayOrder) == Array(0..<10))
  }
}
