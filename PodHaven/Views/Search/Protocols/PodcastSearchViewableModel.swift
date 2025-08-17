// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import SwiftUI

// MARK: - Search Configuration

struct SearchConfiguration {
  let navigationTitle: String
  let idleTitle: String
  let idleDescription: String
  let searchPrompt: String 
}

// MARK: - Protocol

@MainActor
protocol PodcastSearchViewableModel: Observable, AnyObject {
  var searchConfiguration: SearchConfiguration { get }

  // State properties that must be implemented by conforming types
  var state: PodcastSearchState { get set }
  var searchText: String { get set }

  // Internal search method
  func performSearch(with searchText: String) async throws -> [UnsavedPodcast]
}

// MARK: - Search State

enum PodcastSearchState {
  case idle
  case loading
  case loaded([UnsavedPodcast])
  case error(String)
}

// MARK: - Default Implementation

@MainActor
extension PodcastSearchViewableModel {
  @ObservationIgnored private var alert: Alert {
    Container.shared.alert()
  }

  @ObservationIgnored private var sleeper: any Sleepable {
    Container.shared.sleeper()
  }

  private var debounceMilliseconds: Int { 500 }

  var podcasts: [UnsavedPodcast] {
    switch state {
    case .loaded(let podcasts):
      return podcasts
    default:
      return []
    }
  }

  func scheduleSearch() {
    guard let searchableModel = self as? any SearchableModel else { return }

    searchableModel.searchTask?.cancel()

    if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      state = .idle
      return
    }

    searchableModel.searchTask = Task { [weak self] in
      guard let self else { return }
      try? await sleeper.sleep(for: .milliseconds(self.debounceMilliseconds))

      guard !Task.isCancelled else { return }
      await self.performSearchInternal()
    }
  }

  private func performSearchInternal() async {
    let trimmedText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedText.isEmpty else {
      state = .idle
      return
    }

    state = .loading

    do {
      let unsavedPodcasts = try await performSearch(with: trimmedText)

      guard !Task.isCancelled else { return }

      state = .loaded(unsavedPodcasts)
    } catch {
      guard !Task.isCancelled else { return }

      state = .error(ErrorKit.message(for: error))
      alert(ErrorKit.message(for: error))
    }
  }
}

// MARK: - Supporting Protocol for Search Task Management

@MainActor
protocol SearchableModel: AnyObject {
  var searchTask: Task<Void, Never>? { get set }
}
