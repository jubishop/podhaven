// Copyright Justin Bishop, 2026

import IdentifiedCollections
import Logging
import Tagged

extension PlayManager {

  // MARK: - Feedback Commands

  // Pressing the feedback button while its rating is already applied clears it,
  // mirroring the command's isActive toggle affordance (and toggleSaveInCache).
  func toggleRating(_ rating: EpisodeRating, for episodeID: Episode.ID) async {
    let current: EpisodeRating?
    do {
      guard let episode = try await repo.episode(episodeID) else {
        Self.log.warning("toggleRating: episode \(episodeID) not found")
        return
      }
      current = episode.rating
    } catch {
      Self.log.caughtError("toggleRating: failed to load episode \(episodeID)", error)
      return
    }
    let newRating: EpisodeRating? = current == rating ? nil : rating
    Self.log.debug(
      "toggleRating: \(episodeID) \(String(describing: current)) -> \(String(describing: newRating))"
    )
    do {
      try await repo.updateRating(episodeID, rating: newRating)
    } catch {
      Self.log.caughtError(
        "toggleRating: failed to set \(String(describing: newRating)) for episode \(episodeID)",
        error
      )
    }
  }

  // Removes the tag when already present, otherwise adds it (when it still
  // exists), so the feedback button toggles tag membership.
  func toggleTag(_ tagID: Tag.ID, for episodeID: Episode.ID) async {
    let removed: Bool
    do {
      removed = try await repo.removeTag(tagID, from: episodeID)
    } catch {
      Self.log.caughtError(
        "toggleTag: failed to remove tag \(tagID) from episode \(episodeID)",
        error
      )
      return
    }
    if removed {
      Self.log.debug("toggleTag: removed \(tagID) from \(episodeID)")
      return
    }
    guard sharedState.tags[id: tagID] != nil else {
      Self.log.debug("toggleTag: tag \(tagID) no longer exists, ignoring")
      return
    }
    Self.log.debug("toggleTag: added \(tagID) to \(episodeID)")
    do {
      try await repo.addTag(tagID, toEpisodes: [episodeID])
    } catch {
      Self.log.caughtError("toggleTag: failed to add tag \(tagID) to episode \(episodeID)", error)
    }
  }
}
