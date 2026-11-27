// Copyright Justin Bishop, 2026

import Foundation
import Logging

extension PlayManager {
  // MARK: - Cache

  func toggleSaveInCache(_ episodeID: Episode.ID) async {
    let alreadySaved: Bool
    do {
      guard let episode = try await repo.episode(episodeID) else {
        Self.log.warning("toggleSaveInCache: episode \(episodeID) not found")
        return
      }
      alreadySaved = episode.saveInCache
    } catch {
      Self.log.caughtError("toggleSaveInCache: failed to load episode \(episodeID)", error)
      return
    }
    Self.log.debug("toggleSaveInCache: \(episodeID) alreadySaved: \(alreadySaved)")

    if alreadySaved {
      await unsaveInCache(episodeID)
    } else {
      await saveInCache(episodeID)
    }
  }

  private func saveInCache(_ episodeID: Episode.ID) async {
    Self.log.debug("saveInCache: \(episodeID)")
    do {
      try await repo.updateSaveInCache(episodeID, saveInCache: true)
    } catch {
      Self.log.caughtError("saveInCache: failed to set saveInCache for episode \(episodeID)", error)
      return
    }
    do {
      try await cacheManager.downloadToCache(for: episodeID)
    } catch {
      Self.log.caughtError("saveInCache: failed to cache episode \(episodeID)", error)
    }
  }

  private func unsaveInCache(_ episodeID: Episode.ID) async {
    Self.log.debug("unsaveInCache: \(episodeID)")
    do {
      try await repo.updateSaveInCache(episodeID, saveInCache: false)
    } catch {
      Self.log.caughtError(
        "unsaveInCache: failed to unset saveInCache for episode \(episodeID)",
        error
      )
    }
  }
}
