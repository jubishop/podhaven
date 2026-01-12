// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Sharing

extension Container {
  var sharedState: Factory<SharedState> {
    Factory(self) { SharedState() }.scope(.cached)
  }
}

struct SharedState: Sendable {
  @Shared(.inMemory("onDeck")) var onDeck: OnDeck?
  @Shared(.inMemory("playbackStatus")) var playbackStatus: PlaybackStatus = .stopped
  @Shared(.inMemory("playRate")) var playRate: Float = 1.0

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
