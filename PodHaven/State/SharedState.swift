// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import IdentifiedCollections
import Logging
import Tagged

extension Container {
  var sharedState: Factory<SharedState> {
    Factory(self) { SharedState() }.scope(.cached)
  }
}

struct SharedState: Sendable {
  private static let log = Log.as(LogSubsystem.State.shared)

  // MARK: - Persisted State

  @PersistedThreadSafe("currentEpisodeID") var currentEpisodeID: Episode.ID? = nil

  // MARK: - In-Memory State (Observable Broadcasts)

  @Broadcasted var downloadProgress: [Episode.ID: Double] = [:]
  @Broadcasted var isActive: Bool = true
  // OnDeck.== ignores the in-memory playback fields (currentTime,
  // maxPlaybackTime, artwork) that StateManager mutates, so default Equatable
  // dedup would swallow those updates — notify on every write instead.
  @Broadcasted(duplicates: .notifyAlways) var onDeck: OnDeck? = nil
  @Broadcasted var playbackStatus: PlaybackStatus = .stopped
  @Broadcasted var playRate: Float = 1.0
  @Broadcasted var tags: IdentifiedArrayOf<Tag> = []
  @Broadcasted var queuedPodcastEpisodes: [ListablePodcastEpisode] = []
  @Broadcasted var topRecommendations: [Episode.ID] = []

  // MARK: - Download Progress

  func updateDownloadProgress(for episodeID: Episode.ID, progress: Double) {
    Assert.precondition(
      progress >= 0 && progress <= 1,
      "progress must be between 0 and 1 but is \(progress)?"
    )

    Self.log.trace("updating progress for \(episodeID): \(progress)")
    $downloadProgress.update { $0[episodeID] = progress }
  }

  func clearDownloadProgress(for episodeID: Episode.ID) {
    Self.log.debug("clearing progress for \(episodeID)")
    $downloadProgress.update { _ = $0.removeValue(forKey: episodeID) }
  }

  // MARK: - Queue

  func setQueuedPodcastEpisodes(_ episodes: [ListablePodcastEpisode]) {
    $queuedPodcastEpisodes.new(episodes)
  }

  var queueCount: Int {
    queuedPodcastEpisodes.count
  }

  var queuedEpisodeIDs: Set<Episode.ID> {
    Set(queuedPodcastEpisodes.map(\.id))
  }

  var maxQueuePosition: Int? {
    queueCount > 0 ? queueCount - 1 : nil
  }

  // MARK: - Recommendations

  func setTopRecommendations(_ episodeIDs: [Episode.ID]) {
    $topRecommendations.new(episodeIDs)
  }

  // MARK: - Episode Playing Checks

  func isEpisodePlaying(_ episode: any EpisodeFoundational) -> Bool {
    guard let episodeID = episode.episodeID else { return false }
    return isEpisodePlaying(episodeID)
  }

  func isEpisodePlaying(_ episodeID: Episode.ID) -> Bool {
    guard playbackStatus.playing else { return false }
    return onDeck?.id == episodeID
  }

  // MARK: - State Setters

  func setPlaybackStatus(_ status: PlaybackStatus) {
    $playbackStatus.new(status)
  }

  func setPlayRate(_ rate: Float) {
    guard rate > 0 else { return }
    $playRate.new(rate)
  }

  func setTags(_ tags: IdentifiedArrayOf<Tag>) {
    $tags.new(tags)
  }

  // MARK: - Initialization

  fileprivate init() {}
}
