// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import Logging
import Tagged

extension Container {
  @MainActor var podAVPlayer: Factory<PodAVPlayer> {
    Factory(self) { @MainActor in PodAVPlayer() }.scope(.cached)
  }

  var loadEpisodeAsset: Factory<(_ asset: AVURLAsset) async throws -> EpisodeAsset> {
    Factory(self) {
      { asset in
        let (isPlayable, duration) = try await asset.load(.isPlayable, .duration)
        return await EpisodeAsset(
          isPlayable: isPlayable,
          duration: duration.safe,
          playerItemFactory: { AVPlayerItem(asset: asset) }
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

  private var episodeID: Episode.ID?
  private var lastDatabaseUpdateTime: CMTime?

  let currentTimeStream: AsyncStream<CMTime>
  let itemStatusStream: AsyncStream<(AVPlayerItem.Status, Episode.ID)>
  let controlStatusStream: AsyncStream<PlaybackStatus>
  let rateStream: AsyncStream<Float>
  let didPlayToEndStream: AsyncStream<Episode.ID>

  private let currentTimeContinuation: AsyncStream<CMTime>.Continuation
  private let itemStatusContinuation: AsyncStream<(AVPlayerItem.Status, Episode.ID)>.Continuation
  private let controlStatusContinuation: AsyncStream<PlaybackStatus>.Continuation
  private let rateContinuation: AsyncStream<Float>.Continuation
  private let didPlayToEndContinuation: AsyncStream<Episode.ID>.Continuation

  private var periodicTimeObserver: Any?
  private var itemStatusObserver: NSKeyValueObservation?
  private var timeControlStatusObserver: NSKeyValueObservation?
  private var rateObserver: NSKeyValueObservation?
  private var didPlayToEndTask: Task<Void, Never>?

  // MARK: - Initialization

  fileprivate init() {
    (currentTimeStream, currentTimeContinuation) = AsyncStream.makeStream(of: CMTime.self)
    (itemStatusStream, itemStatusContinuation) = AsyncStream.makeStream(
      of: (AVPlayerItem.Status, Episode.ID).self
    )
    (controlStatusStream, controlStatusContinuation) = AsyncStream.makeStream(
      of: PlaybackStatus.self
    )
    (rateStream, rateContinuation) = AsyncStream.makeStream(of: Float.self)
    (didPlayToEndStream, didPlayToEndContinuation) = AsyncStream.makeStream(of: Episode.ID.self)
  }

  // MARK: - Loading

  func load(_ podcastEpisode: PodcastEpisode) async throws(PlaybackError) -> PodcastEpisode {
    Self.log.debug("load: \(podcastEpisode.toString)")

    episodeID = nil
    lastDatabaseUpdateTime = nil
    let (podcastEpisode, playableItem) = try await loadAsset(for: podcastEpisode)
    episodeID = podcastEpisode.id
    lastDatabaseUpdateTime = podcastEpisode.currentTime
    avPlayer.replaceCurrent(with: playableItem)

    return podcastEpisode
  }

  private func loadAsset(for podcastEpisode: PodcastEpisode) async throws(PlaybackError)
    -> (podcastEpisode: PodcastEpisode, playableItem: any AVPlayableItem)
  {
    Self.log.debug("loadAsset: \(podcastEpisode.toString)")

    let episodeAsset: EpisodeAsset = try await performLoadAsset(for: podcastEpisode)

    guard episodeAsset.isPlayable
    else { throw PlaybackError.mediaNotPlayable(podcastEpisode) }

    do {
      try await repo.updateDuration(podcastEpisode.id, duration: episodeAsset.duration)
      guard let updatedPodcastEpisode = try await repo.podcastEpisode(podcastEpisode.id)
      else { throw PlaybackError.durationUpdateFailure(podcastEpisode: podcastEpisode) }

      return (updatedPodcastEpisode, episodeAsset.playerItem())
    } catch {
      throw PlaybackError.caught(error)
    }
  }
  private func performLoadAsset(for podcastEpisode: PodcastEpisode) async throws(PlaybackError)
    -> EpisodeAsset
  {
    do {
      guard let cachedURL = podcastEpisode.episode.cachedURL else {
        return try await loadEpisodeAsset(
          AVURLAsset(url: podcastEpisode.episode.mediaURL.rawValue)
        )
      }
      do {
        return try await loadEpisodeAsset(AVURLAsset(url: cachedURL.rawValue))
      } catch {
        return try await loadEpisodeAsset(
          AVURLAsset(url: podcastEpisode.episode.mediaURL.rawValue)
        )
      }
    } catch {
      throw PlaybackError.loadFailure(podcastEpisode: podcastEpisode, caught: error)
    }
  }

  func clear() {
    Self.log.debug("clear: executing")
    removeObservers()
    episodeID = nil
    lastDatabaseUpdateTime = nil
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

  func setRate(_ rate: Float) {
    Self.log.debug("setRate: \(rate)")

    avPlayer.setDefaultRate(rate)
    if avPlayer.timeControlStatus != .paused {
      Self.log.debug("Setting rate because timeControlStatus is: \(avPlayer.timeControlStatus)")
      avPlayer.setRate(rate)
    }
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
        Task { [weak self] in
          guard let self else { return }
          do {
            try await saveCurrentTime(time)
          } catch {
            Self.log.error(error)
          }
          await addPeriodicTimeObserver()
        }
      } else {
        Self.log.debug("seek: to \(time) interrupted")
      }
    }
  }

  private func saveCurrentTime(_ currentTime: CMTime) async throws {
    guard let episodeID
    else { throw PlaybackError.settingCurrentTimeOnNil(currentTime) }

    do {
      try await repo.updateCurrentTime(episodeID, currentTime: currentTime)
      lastDatabaseUpdateTime = currentTime
      Self.log.debug("saveCurrentTime: saved \(currentTime) for \(episodeID)")
    } catch {
      Self.log.error(error)
    }
  }

  // MARK: - Change Handlers

  private func handleCurrentTimeChange(_ currentTime: CMTime) async throws {
    guard let episodeID
    else { throw PlaybackError.settingCurrentTimeOnNil(currentTime) }

    // Only update the database every 3 seconds
    if currentTime.seconds - (lastDatabaseUpdateTime ?? .zero).seconds >= 3.0 {
      try await saveCurrentTime(currentTime)
    }

    // Always yield to the stream for UI updates (250ms)
    Self.log.trace("handleCurrentTimeChange to: \(currentTime) for \(episodeID)")
    currentTimeContinuation.yield(currentTime)
  }

  // MARK: - Transient State Tracking

  func addObservers() {
    addItemStatusObserver()
    addPeriodicTimeObserver()
    addTimeControlStatusObserver()
    addRateObserver()
    addDidPlayToEndObserver()
  }

  func removeObservers() {
    removeItemStatusObserver()
    removePeriodicTimeObserver()
    removeTimeControlStatusObserver()
    removeRateObserver()
    removeDidPlayToEndObserver()
  }

  private func addItemStatusObserver() {
    guard itemStatusObserver == nil else { return }

    guard let currentItem = avPlayer.current, let episodeID else { return }
    itemStatusObserver = currentItem.observeStatus(options: [.initial, .new]) {
      [weak self] status in
      guard let self else { return }
      itemStatusContinuation.yield((status, episodeID))
    }
  }

  private func addPeriodicTimeObserver() {
    guard periodicTimeObserver == nil else { return }

    Self.log.debug("addPeriodicTimeObserver: registering using player's internal queue")
    periodicTimeObserver = avPlayer.addPeriodicTimeObserver(
      forInterval: .milliseconds(250),
      queue: nil
    ) { [weak self] currentTime in
      guard let self else { return }
      Task { [weak self, currentTime] in
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
      Self.log.debug("removePeriodicTimeObserver: unregistering observer")
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

  private func addDidPlayToEndObserver() {
    guard didPlayToEndTask == nil else { return }

    didPlayToEndTask = Task { [weak self] in
      guard let self else { return }
      for await _ in notifications(AVPlayerItem.didPlayToEndTimeNotification) {
        guard !Task.isCancelled else { return }
        guard let episodeID else { return }
        didPlayToEndContinuation.yield(episodeID)
      }
    }
  }

  private func removeDidPlayToEndObserver() {
    if let didPlayToEndTask {
      didPlayToEndTask.cancel()
      self.didPlayToEndTask = nil
    }
  }
}
