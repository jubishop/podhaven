// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Logging

extension Container {
  @MainActor var cacheState: Factory<CacheState> {
    Factory(self) { @MainActor in CacheState() }.scope(.cached)
  }
}

@Observable @MainActor class CacheState {
  private static let log = Log.as(LogSubsystem.Cache.state)

  // MARK: - State Management

  private var progressByEpisode: [Episode.ID: Double] = [:]

  // MARK: - State Getters

  func progress(_ episodeID: Episode.ID) -> Double? {
    progressByEpisode[episodeID]
  }

  // MARK: - State Setters

  func updateProgress(for episodeID: Episode.ID, progress: Double) {
    Assert.precondition(
      progress >= 0 && progress <= 1,
      "progress must be between 0 and 1 but is \(progress)?"
    )

    Self.log.trace("updating progress for \(episodeID): \(progress)")
    progressByEpisode[episodeID] = progress
  }

  func clearProgress(for episodeID: Episode.ID) {
    Self.log.debug("clearing progress for \(episodeID)")
    progressByEpisode.removeValue(forKey: episodeID)
  }

  // MARK: - Initialization

  fileprivate init() {}
}
