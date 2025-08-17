// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import SwiftUI

@Observable @MainActor
class PodcastSearchViewModel {
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.sleeper) private var sleeper

  // MARK: - Configuration

  private let debounceMilliseconds: Int = 500

  // MARK: - State

  enum State {
    case idle
    case loading
    case loaded([UnsavedPodcast])
    case error(String)
  }

  var state: State = .idle
  var searchText = "" {
    didSet {
      if searchText != oldValue {
        searchTask?.cancel()
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          state = .idle
        } else {
          scheduleSearch()
        }
      }
    }
  }

  @ObservationIgnored private var searchTask: Task<Void, Never>?
  private let searchClosure: (String) async throws -> [UnsavedPodcast]

  // MARK: - Computed Properties

  var podcasts: [UnsavedPodcast] {
    switch state {
    case .loaded(let podcasts):
      return podcasts
    default:
      return []
    }
  }

  // MARK: - Initialization

  init(searchClosure: @escaping (String) async throws -> [UnsavedPodcast]) {
    self.searchClosure = searchClosure
  }

  // MARK: - Private Methods

  private func scheduleSearch() {
    searchTask = Task { [weak self] in
      guard let self else { return }
      try? await sleeper.sleep(for: .milliseconds(self.debounceMilliseconds))

      guard !Task.isCancelled else { return }
      await self.performSearch()
    }
  }

  private func performSearch() async {
    let trimmedText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedText.isEmpty else {
      state = .idle
      return
    }

    state = .loading

    do {
      let unsavedPodcasts = try await searchClosure(trimmedText)

      guard !Task.isCancelled else { return }

      state = .loaded(unsavedPodcasts)
    } catch {
      guard !Task.isCancelled else { return }

      state = .error(ErrorKit.message(for: error))
      alert(ErrorKit.message(for: error))
    }
  }

  // MARK: - Cleanup

  deinit {
    searchTask?.cancel()
  }
}
