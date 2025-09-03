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

  private var activeBackgroundTaskIDs: [Episode.ID: DownloadTaskID] = [:]
  private var progressByEpisode: [Episode.ID: Double] = [:]

  // MARK: - State Getters

  func isDownloading(_ episodeID: Episode.ID) -> Bool {
    activeBackgroundTaskIDs[episodeID] != nil
  }

  func getBackgroundTaskIdentifier(_ episodeID: Episode.ID) -> DownloadTaskID? {
    activeBackgroundTaskIDs[episodeID]
  }

  func progress(_ episodeID: Episode.ID) -> Double? {
    progressByEpisode[episodeID]
  }

  // MARK: - State Setters

  func setDownloadTaskID(_ episodeID: Episode.ID, taskID: DownloadTaskID) {
    activeBackgroundTaskIDs[episodeID] = taskID
  }

  func updateProgress(for episodeID: Episode.ID, progress: Double) {
    progressByEpisode[episodeID] = progress
  }

  func updateProgress(for guid: MediaGUID, progress: Double) async {
    // Helper for delegate when only MediaGUID is known
    do {
      let repo: any Databasing = Container.shared.repo()
      if let episode = try await repo.episode(guid) {
        progressByEpisode[episode.id] = progress
      }
    } catch {
      // Ignore
    }
  }

  func removeDownloadTask(_ episodeID: Episode.ID) {
    activeBackgroundTaskIDs.removeValue(forKey: episodeID)
    progressByEpisode.removeValue(forKey: episodeID)
  }

  func markFinished(_ episodeID: Episode.ID) {
    removeDownloadTask(episodeID)
  }

  func markFailed(_ episodeID: Episode.ID, error: Error) {
    removeDownloadTask(episodeID)
  }

  // MARK: - Initialization

  fileprivate init() {}
}
