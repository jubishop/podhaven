// Copyright Justin Bishop, 2026

import Foundation

struct EpisodeDetailSource: Sendable {
  enum MissingSavedResolution: Sendable {
    case display(DisplayedEpisode)
    case dismiss(message: String)
  }

  let initialEpisode: DisplayedEpisode
  private let listedEpisode: ListedEpisode?
  private let unsavedFallback: UnsavedPodcastEpisode?

  init(episode: DisplayedEpisode) {
    initialEpisode = episode
    listedEpisode = nil
    unsavedFallback = Self.unsavedFallback(for: episode.getUnsavedPodcastEpisode())
  }

  init(listedEpisode: ListedEpisode) {
    initialEpisode = DisplayedEpisode(EpisodeDetailSnapshot(listedEpisode))
    self.listedEpisode = listedEpisode
    unsavedFallback = Self.unsavedFallback(for: listedEpisode.getUnsavedPodcastEpisode())
  }

  func savedEpisode(
    using repo: any Databasing,
    currentEpisode: DisplayedEpisode
  ) async throws -> PodcastEpisode? {
    try await repo.podcastEpisode(currentEpisode.mediaGUID)
  }

  func missingSavedResolution() -> MissingSavedResolution {
    if let unsavedFallback {
      return .display(DisplayedEpisode(unsavedFallback))
    }

    return .dismiss(message: "This episode is no longer available.")
  }

  func deletedObservedPresentation(_ podcastEpisode: PodcastEpisode) throws -> DisplayedEpisode {
    DisplayedEpisode(try podcastEpisode.toOriginalUnsavedPodcastEpisode())
  }

  func getOrCreatePodcastEpisode(currentEpisode: DisplayedEpisode) async throws -> PodcastEpisode {
    if let listedEpisode {
      return try await listedEpisode.getOrCreatePodcastEpisode()
    }

    return try await currentEpisode.getOrCreatePodcastEpisode()
  }

  private static func unsavedFallback(
    for unsavedPodcastEpisode: UnsavedPodcastEpisode?
  ) -> UnsavedPodcastEpisode? {
    guard let unsavedPodcastEpisode else { return nil }

    do {
      return try unsavedPodcastEpisode.toOriginalUnsavedPodcastEpisode()
    } catch {
      Assert.fatal(
        """
        Cannot build UnsavedPodcastEpisode fallback \
        for episode: \(unsavedPodcastEpisode.toString). \
        Error: \(error)
        """
      )
    }
  }
}
