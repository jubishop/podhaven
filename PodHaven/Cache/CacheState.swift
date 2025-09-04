// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation

extension Container {
  @MainActor var cacheState: Factory<CacheState> {
    Factory(self) { @MainActor in CacheState() }.scope(.cached)
  }
}

@Observable @MainActor class CacheState {
  // MARK: - State Management

  private var progressByEpisode: [Episode.ID: Double] = [:]

  // MARK: - State Getters

  func progress(_ episodeID: Episode.ID) -> Double? {
    progressByEpisode[episodeID]
  }

  // MARK: - State Setters

  func updateProgress(for episodeID: Episode.ID, progress: Double) {
    progressByEpisode[episodeID] = progress
  }

  func clearProgress(for episodeID: Episode.ID) {
    progressByEpisode.removeValue(forKey: episodeID)
  }

  // MARK: - Initialization

  fileprivate init() {}
}
