// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import Logging
import Semaphore

extension Container {
  @MainActor var podAVPlayer: Factory<PodAVPlayer> {
    Factory(self) { @MainActor in PodAVPlayer() }.scope(.cached)
  }

  var loadEpisodeAsset: Factory<(_ episode: Episode) async throws -> EpisodeAsset> {
    Factory(self) {
      { episode in
        let asset = AVURLAsset(url: episode.media.rawValue, episodeID: episode.id)
        let (isPlayable, duration) = try await asset.load(.isPlayable, .duration)
        return await EpisodeAsset(
          playerItem: AVPlayerItem(asset: asset),
          isPlayable: isPlayable,
          duration: duration
        )
      }
    }
  }
}

@MainActor class PodAVPlayer {
  @DynamicInjected(\.avPlayer) private var avPlayer
  @DynamicInjected(\.loadEpisodeAsset) private var loadEpisodeAsset
  @DynamicInjected(\.notifications) private var notifications
  @DynamicInjected(\.repo) private var repo

  nonisolated private static let log = Log.as(LogSubsystem.Play.avPlayer)

  // MARK: - State Management

  typealias LoadedPodcastEpisode = (
    podcastEpisode: PodcastEpisode,
    playableItem: any AVPlayableItem
  )
  private var podcastEpisode: PodcastEpisode?

  let currentTimeStream: AsyncStream<CMTime>
  let itemStatusStream: AsyncStream<(status: AVPlayerItem.Status, episodeID: Episode.ID?)>
  let controlStatusStream: AsyncStream<PlaybackStatus>
  let rateStream: AsyncStream<Float>

  private let currentTimeContinuation: AsyncStream<CMTime>.Continuation
  private let itemStatusContinuation:
    AsyncStream<(status: AVPlayerItem.Status, episodeID: Episode.ID?)>.Continuation
  private let controlStatusContinuation: AsyncStream<PlaybackStatus>.Continuation
  private let rateContinuation: AsyncStream<Float>.Continuation

  private var periodicTimeObserver: Any?
  private var itemStatusObserver: NSKeyValueObservation?
  private var timeControlStatusObserver: NSKeyValueObservation?
  private var rateObserver: NSKeyValueObservation?

  // MARK: - Initialization

  fileprivate init() {
    (currentTimeStream, currentTimeContinuation) = AsyncStream.makeStream(of: CMTime.self)
    (itemStatusStream, itemStatusContinuation) = AsyncStream.makeStream(
      of: (status: AVPlayerItem.Status, episodeID: Episode.ID?).self
    )
    (controlStatusStream, controlStatusContinuation) = AsyncStream.makeStream(
      of: PlaybackStatus.self
    )
    (rateStream, rateContinuation) = AsyncStream.makeStream(of: Float.self)
  }

  // MARK: - Loading

  func load(_ podcastEpisode: PodcastEpisode) async throws(PlaybackError) -> PodcastEpisode {
    Self.log.debug("load: \(podcastEpisode.toString)")

    self.podcastEpisode = nil
    let (podcastEpisode, playableItem) = try await loadAsset(for: podcastEpisode)
    self.podcastEpisode = podcastEpisode
    avPlayer.replaceCurrent(with: playableItem)

    return podcastEpisode
  }

  private func loadAsset(for podcastEpisode: PodcastEpisode) async throws(PlaybackError)
    -> LoadedPodcastEpisode
  {
    Self.log.debug("loadAsset: \(podcastEpisode.toString)")

    let episodeAsset: EpisodeAsset
    do {
      episodeAsset = try await loadEpisodeAsset(podcastEpisode.episode)
    } catch {
      throw PlaybackError.loadFailure(podcastEpisode: podcastEpisode, caught: error)
    }

    guard episodeAsset.isPlayable
    else { throw PlaybackError.mediaNotPlayable(podcastEpisode) }

    var episode = podcastEpisode.episode
    episode.duration = episodeAsset.duration

    do {
      try await repo.updateDuration(podcastEpisode.id, episode.duration)
    } catch {
      Self.log.error(error)
    }

    return (
      PodcastEpisode(
        podcast: podcastEpisode.podcast,
        episode: episode
      ),
      episodeAsset.playerItem
    )
  }

  func clear() {
    Self.log.debug("clear: executing")
    removeObservers()
    podcastEpisode = nil
    avPlayer.replaceCurrent(with: nil)
  }

  // MARK: - Playback Controls

  func play() {
    Self.log.debug("play: executing")
    avPlayer.play()
  }

  func pause() {
    Self.log.debug("pause: executing")
    avPlayer.pause()
  }

  func toggle() {
    let currentStatus = avPlayer.timeControlStatus
    Self.log.debug("toggle: executing (current status: \(currentStatus))")
    currentStatus == .paused
      ? play()
      : pause()
  }

  // MARK: - Seeking

  func seekForward(_ duration: CMTime) {
    Self.log.debug("seekForward: \(duration)")
    seek(to: avPlayer.currentTime() + duration)
  }

  func seekBackward(_ duration: CMTime) {
    Self.log.debug("seekBackward: \(duration)")
    seek(to: avPlayer.currentTime() - duration)
  }

  func seek(to time: CMTime) {
    Self.log.debug("seek: \(time)")

    removePeriodicTimeObserver()
    currentTimeContinuation.yield(time)

    avPlayer.seek(to: time) { [weak self] completed in
      guard let self else { return }

      if completed {
        Self.log.debug("seek: to \(time) completed")
        Task { @MainActor [weak self] in
          guard let self else { return }
          addPeriodicTimeObserver()
        }
      } else {
        Self.log.debug("seek: to \(time) interrupted")
      }
    }
  }

  // MARK: - Change Handlers

  private func handleCurrentTimeChange(_ currentTime: CMTime) async throws {
    guard let podcastEpisode
    else { throw PlaybackError.settingCurrentTimeOnNil(currentTime) }

    try await repo.updateCurrentTime(podcastEpisode.id, currentTime)

    Self.log.trace("handleCurrentTimeChange to: \(currentTime) for \(podcastEpisode.toString)")
    currentTimeContinuation.yield(currentTime)
  }

  // MARK: - Transient State Tracking

  func addObservers() {
    addItemStatusObserver()
    addPeriodicTimeObserver()
    addTimeControlStatusObserver()
    addRateObserver()
  }

  func removeObservers() {
    removeItemStatusObserver()
    removePeriodicTimeObserver()
    removeTimeControlStatusObserver()
    removeRateObserver()
  }

  private func addItemStatusObserver() {
    guard let currentItem = avPlayer.current else { return }
    removeItemStatusObserver()

    let episodeID = currentItem.episodeID
    itemStatusObserver = currentItem.observeStatus(options: [.initial, .new]) {
      [weak self] status in
      guard let self else { return }
      itemStatusContinuation.yield((status: status, episodeID: episodeID))
    }
  }

  private func addPeriodicTimeObserver() {
    guard periodicTimeObserver == nil else { return }

    periodicTimeObserver = avPlayer.addPeriodicTimeObserver(
      forInterval: CMTime.seconds(1),
      queue: .global(qos: .utility)
    ) { [weak self] currentTime in
      guard let self else { return }
      Task { [weak self] in
        guard let self else { return }
        do {
          try await self.handleCurrentTimeChange(currentTime)
        } catch {
          Self.log.error(error)
        }
      }
    }
  }

  private func addTimeControlStatusObserver() {
    guard timeControlStatusObserver == nil else { return }

    timeControlStatusObserver = avPlayer.observeTimeControlStatus(options: [.initial, .new]) {
      [weak self] status in
      guard let self else { return }
      controlStatusContinuation.yield(PlaybackStatus(status))
    }
  }

  private func addRateObserver() {
    guard rateObserver == nil else { return }

    rateObserver = avPlayer.observeRate(options: [.initial, .new]) { [weak self] rate in
      guard let self else { return }
      rateContinuation.yield(rate)
    }
  }

  private func removeItemStatusObserver() {
    if itemStatusObserver != nil {
      self.itemStatusObserver = nil
    }
  }

  private func removePeriodicTimeObserver() {
    if let periodicTimeObserver {
      avPlayer.removeTimeObserver(periodicTimeObserver)
      self.periodicTimeObserver = nil
    }
  }

  private func removeTimeControlStatusObserver() {
    if timeControlStatusObserver != nil {
      self.timeControlStatusObserver = nil
    }
  }

  private func removeRateObserver() {
    if rateObserver != nil {
      self.rateObserver = nil
    }
  }

}
