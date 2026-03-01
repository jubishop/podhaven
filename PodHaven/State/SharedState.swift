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
  @DynamicInjected(\.widgetSnapshotWriter) private var widgetSnapshotWriter

  private static let log = Log.as(LogSubsystem.State.shared)

  // MARK: - Persisted State

  @PersistedBroadcast("currentEpisodeID") private var storedCurrentEpisodeID: Int? = nil

  // MARK: - In-Memory State (Observable Broadcasts)

  @ObservableBroadcast var downloadProgress: [Episode.ID: Double] = [:]
  @ObservableBroadcast var isActive: Bool = true
  @ObservableBroadcast var onDeck: OnDeck? = nil
  @ObservableBroadcast var playbackStatus: PlaybackStatus = .stopped
  @ObservableBroadcast var playRate: Float = 1.0
  @ObservableBroadcast var tags: IdentifiedArrayOf<Tag> = []
  @ObservableBroadcast var queuedPodcastEpisodes: [PodcastEpisode] = []

  // MARK: - Current Episode ID (Persisted)

  var currentEpisodeID: Episode.ID? {
    guard let currentEpisodeInt = storedCurrentEpisodeID,
      let currentEpisodeInt64 = Int64(exactly: currentEpisodeInt)
    else { return nil }
    return Episode.ID(rawValue: currentEpisodeInt64)
  }

  func setCurrentEpisodeID(_ episodeID: Episode.ID?) {
    guard let newEpisodeID = episodeID else {
      $storedCurrentEpisodeID.new(nil)
      return
    }
    $storedCurrentEpisodeID.new(Int(exactly: newEpisodeID.rawValue))
  }

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

  func setQueuedPodcastEpisodes(_ episodes: [PodcastEpisode]) {
    $queuedPodcastEpisodes.new(episodes)
    Task { await widgetSnapshotWriter.queueChanged() }
  }

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
    $playbackStatus.new(status)
    Task { await widgetSnapshotWriter.playbackStatusChanged() }
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
