// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import IdentifiedCollections
import Logging
import SwiftUI
import Tagged

extension Container {
  var sharedState: Factory<SharedState> {
    Factory(self) { SharedState() }.scope(.cached)
  }
}

struct SharedState: Sendable {
  private static let log = Log.as(LogSubsystem.State.shared)

  // MARK: - Persisted State

  // Only StateManager should write this.
  @PersistedBroadcast("currentEpisodeID") var currentEpisodeID: Episode.ID? = nil

  // Persisted so the Up Next "Recommended" section seeds from the prior
  // session on cold launch instead of sitting empty until the engine warms.
  @PersistedBroadcast("recommendedEpisodePool") var recommendedEpisodePool: [Episode.ID] = []

  // MARK: - In-Memory State (Observable Broadcasts)

  @Broadcasted var downloadProgress: [Episode.ID: Double] = [:]
  @Broadcasted var scenePhase: ScenePhase = .active
  // Only StateManager should write this. Use `.notifyAlways`, not `.equatable`:
  // artwork loads as an artwork-only write that `==` can't detect, and the
  // observation task's guarded no-op writes must still wake observers.
  @Broadcasted(duplicates: .notifyAlways) var onDeck: OnDeck? = nil
  @Broadcasted var playbackStatus: PlaybackStatus = .stopped
  // When set, PlayManager stops at the current episode's end instead of
  // auto-advancing, then clears this back to false (single-use sleep stop).
  @Broadcasted var stopAfterCurrentEpisode: Bool = false
  @Broadcasted var playRate: Float = 1.0
  @Broadcasted var tags: IdentifiedArrayOf<Tag> = []
  // Only StateManager should write this. Mirrors the smartList table so
  // Navigation can resolve a smartList destination synchronously.
  @Broadcasted var smartLists: IdentifiedArrayOf<SmartList> = []
  @Broadcasted var queuedPodcastEpisodes: [ListablePodcastEpisode] = []

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

  func setRecommendedEpisodePool(_ episodeIDs: [Episode.ID]) {
    $recommendedEpisodePool.new(episodeIDs)
  }

  // MARK: - On-Deck & Playing Checks

  // Identity checks read `currentEpisodeID`, never `onDeck`: playback time
  // updates rewrite `onDeck`, so reading it here would
  // pull every tick into the tracked region of any view that only cares about
  // which episode is current. `currentEpisodeID` moves only on episode
  // transitions, set in lockstep with `onDeck` by `StateManager`.
  func isOnDeck(_ episode: any EpisodeFoundational) -> Bool {
    guard let episodeID = episode.episodeID else { return false }
    return currentEpisodeID == episodeID
  }

  func isEpisodePlaying(_ episode: any EpisodeFoundational) -> Bool {
    guard playbackStatus.playing else { return false }
    return isOnDeck(episode)
  }

  func isEpisodePlaying(_ episodeID: Episode.ID) -> Bool {
    guard playbackStatus.playing else { return false }
    return currentEpisodeID == episodeID
  }

  // MARK: - State Setters

  func setPlaybackStatus(_ status: PlaybackStatus) {
    $playbackStatus.new(status)
  }

  func setStopAfterCurrentEpisode(_ enabled: Bool) {
    $stopAfterCurrentEpisode.new(enabled)
  }

  func setPlayRate(_ rate: Float) {
    guard rate > 0 else { return }
    $playRate.new(rate)
  }

  func setTags(_ tags: IdentifiedArrayOf<Tag>) {
    $tags.new(tags)
  }

  func setSmartLists(_ smartLists: IdentifiedArrayOf<SmartList>) {
    $smartLists.new(smartLists)
  }

  // MARK: - Initialization

  fileprivate init() {}
}
