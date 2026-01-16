// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Logging
import Sharing
import Tagged

extension Container {
  var sharedState: Factory<SharedState> {
    Factory(self) { SharedState() }.scope(.cached)
  }
}

struct SharedState: Sendable {
  private static let log = Log.as(LogSubsystem.State.shared)

  @Shared(.appStorage("currentEpisodeID")) private var storedCurrentEpisodeID: Int?
  @Shared(.inMemory("downloadProgress")) var downloadProgress: [Episode.ID: Double] = [:]
  @Shared(.inMemory("onDeck")) var onDeck: OnDeck?
  @Shared(.inMemory("playbackStatus")) var playbackStatus: PlaybackStatus = .stopped
  @Shared(.inMemory("playRate")) var playRate: Float = 1.0

  // MARK: - Current Episode ID (Persisted)

  var currentEpisodeID: Episode.ID? {
    guard let currentEpisodeInt = storedCurrentEpisodeID,
      let currentEpisodeInt64 = Int64(exactly: currentEpisodeInt)
    else { return nil }
    return Episode.ID(rawValue: currentEpisodeInt64)
  }

  func setCurrentEpisodeID(_ episodeID: Episode.ID?) {
    $storedCurrentEpisodeID.withLock { stored in
      guard let newEpisodeID = episodeID else {
        stored = nil
        return
      }
      stored = Int(exactly: newEpisodeID.rawValue)
    }
  }

  // MARK: - Download Progress

  func updateDownloadProgress(for episodeID: Episode.ID, progress: Double) {
    Assert.precondition(
      progress >= 0 && progress <= 1,
      "progress must be between 0 and 1 but is \(progress)?"
    )

    Self.log.trace("updating progress for \(episodeID): \(progress)")
    $downloadProgress.withLock { $0[episodeID] = progress }
  }

  func clearDownloadProgress(for episodeID: Episode.ID) {
    Self.log.debug("clearing progress for \(episodeID)")
    _ = $downloadProgress.withLock { $0.removeValue(forKey: episodeID) }
  }

  // MARK: - Queue State

  private let queueBroadcast = Broadcast<[PodcastEpisode]>([])

  var queuedPodcastEpisodes: [PodcastEpisode] {
    queueBroadcast.current
  }

  func setQueuedPodcastEpisodes(_ episodes: [PodcastEpisode]) {
    queueBroadcast.new(episodes)
  }

  // MARK: - Queue Streams

  func queuedPodcastEpisodesStream() -> AsyncStream<[PodcastEpisode]> {
    queueBroadcast.stream()
  }

  // MARK: - Queue Derived Properties

  var queueCount: Int {
    queuedPodcastEpisodes.count
  }

  var queuedEpisodeIDs: Set<Episode.ID> {
    Set(queuedPodcastEpisodes.map(\.episode.id))
  }

  var maxQueuePosition: Int? {
    queueCount > 0 ? queueCount - 1 : nil
  }

  // MARK: - Episode Playing Checks

  func isEpisodePlaying(_ episode: any EpisodeInformable) -> Bool {
    guard let episodeID = episode.episodeID else { return false }
    return isEpisodePlaying(episodeID)
  }

  func isEpisodePlaying(_ episodeID: Episode.ID) -> Bool {
    guard playbackStatus.playing else { return false }
    return onDeck?.id == episodeID
  }

  // MARK: - State Setters

  func setPlaybackStatus(_ status: PlaybackStatus) {
    $playbackStatus.withLock { $0 = status }
  }

  func setPlayRate(_ rate: Float) {
    guard rate > 0 else { return }
    $playRate.withLock { $0 = rate }
  }

  // MARK: - Initialization

  fileprivate init() {}
}
