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

  private var activeDownloadTasks: [Episode.ID: DownloadTask] = [:]

  // MARK: - State Getters

  func isDownloading(_ episodeID: Episode.ID) -> Bool {
    activeDownloadTasks[episodeID] != nil
  }

  func getDownloadTask(_ episodeID: Episode.ID) -> DownloadTask? {
    activeDownloadTasks[episodeID]
  }

  // MARK: - State Setters

  func setDownloadTask(_ episodeID: Episode.ID, downloadTask: DownloadTask) {
    activeDownloadTasks[episodeID] = downloadTask
  }

  func removeDownloadTask(_ episodeID: Episode.ID) {
    activeDownloadTasks.removeValue(forKey: episodeID)
  }

  // MARK: - Initialization

  fileprivate init() {}
}
