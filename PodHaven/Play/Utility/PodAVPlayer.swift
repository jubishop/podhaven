// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import IdentifiedCollections
import Logging
import Semaphore

extension Container {
  @MainActor var podAVPlayer: Factory<PodAVPlayer> {
    Factory(self) { @MainActor in PodAVPlayer() }.scope(.cached)
  }

  var loadEpisodeAsset: Factory<(_ mediaURL: MediaURL) async throws -> EpisodeAsset> {
    Factory(self) {
      { mediaURL in
        let asset = AVURLAsset(url: mediaURL.rawValue)
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
  @DynamicInjected(\.avQueuePlayer) private var avQueuePlayer
  @DynamicInjected(\.loadEpisodeAsset) private var loadEpisodeAsset
  @DynamicInjected(\.notifications) private var notifications
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.repo) private var repo

  private let log = Log.as(LogSubsystem.Play.avPlayer)

  // MARK: - State Management

  typealias LoadedPodcastEpisode = (
    podcastEpisode: PodcastEpisode,
    playableItem: any AVPlayableItem
  )
  private(set) var podcastEpisode: PodcastEpisode?
  private var preSeekStatus: AVPlayer.TimeControlStatus?

  let currentTimeStream: AsyncStream<CMTime>
  let currentItemStream: AsyncStream<PodcastEpisode?>
  let controlStatusStream: AsyncStream<AVPlayer.TimeControlStatus>
  private let currentTimeContinuation: AsyncStream<CMTime>.Continuation
  private let currentItemContinuation: AsyncStream<PodcastEpisode?>.Continuation
  private let controlStatusContinuation: AsyncStream<AVPlayer.TimeControlStatus>.Continuation

  private var periodicTimeObserver: Any?
  private var currentItemObserver: NSKeyValueObservation?
  private var timeControlStatusObserver: NSKeyValueObservation?
  private var observeNextEpisodeTask: Task<Void, Never>?
  private var setNextEpisodeTask: Task<Void, any Error>?

  // MARK: - Initialization

  fileprivate init() {
    (currentTimeStream, currentTimeContinuation) = AsyncStream.makeStream(of: CMTime.self)
    (currentItemStream, currentItemContinuation) = AsyncStream.makeStream(of: PodcastEpisode?.self)
    (controlStatusStream, controlStatusContinuation) = AsyncStream.makeStream(
      of: AVPlayer.TimeControlStatus.self
    )
  }

  // MARK: - Loading

  func stop() {
    log.debug("stop: executing")
    removeObservers()
    podcastEpisode = nil
    preSeekStatus = nil
    avQueuePlayer.removeAllItems()
  }

  func load(_ podcastEpisode: PodcastEpisode) async throws(PlaybackError) -> PodcastEpisode {
    log.debug("load: \(podcastEpisode.toString)")

    avQueuePlayer.removeAllItems()
    preSeekStatus = nil
    self.podcastEpisode = nil
    let (podcastEpisode, playableItem) = try await loadAsset(for: podcastEpisode)
    self.podcastEpisode = podcastEpisode
    avQueuePlayer.insert(playableItem, after: nil)

    return podcastEpisode
  }

  private func loadAsset(for podcastEpisode: PodcastEpisode) async throws(PlaybackError)
    -> LoadedPodcastEpisode
  {
    log.debug("loadAsset: \(podcastEpisode.toString)")

    let episodeAsset: EpisodeAsset
    do {
      episodeAsset = try await loadEpisodeAsset(podcastEpisode.episode.media)
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
      log.error(error)
    }

    return (
      PodcastEpisode(
        podcast: podcastEpisode.podcast,
        episode: episode
      ),
      episodeAsset.playerItem
    )
  }

  // MARK: - Playback Controls

  func play() {
    log.debug("playing")
    preSeekStatus = .playing
    avQueuePlayer.play()
  }

  func pause(overwritePreSeekStatus: Bool = true) {
    log.debug("pausing")
    if overwritePreSeekStatus {
      preSeekStatus = .paused
    }
    avQueuePlayer.pause()
  }

  func toggle() {
    log.debug("toggling")
    avQueuePlayer.timeControlStatus == .paused
      ? play()
      : pause()
  }

  // MARK: - Seeking

  func seekForward(_ duration: CMTime) {
    log.trace("seekForward: \(duration)")
    seek(to: avQueuePlayer.currentTime() + duration)
  }

  func seekBackward(_ duration: CMTime) {
    log.trace("seekBackward: \(duration)")
    seek(to: avQueuePlayer.currentTime() - duration)
  }

  func seek(to time: CMTime) {
    log.trace("seek: \(time)")

    removePeriodicTimeObserver()
    currentTimeContinuation.yield(time)
    preSeekStatus = preSeekStatus ?? avQueuePlayer.timeControlStatus
    pause(overwritePreSeekStatus: false)

    avQueuePlayer.seek(to: time) { [weak self] completed in
      guard let self else { return }

      if completed {
        log.trace("seek: to \(time) completed")
        Task { @MainActor [weak self] in
          guard let self else { return }
          if let preSeekStatus {
            self.preSeekStatus = nil
            if preSeekStatus != .paused { play() }
          }
          addPeriodicTimeObserver()
        }
      } else {
        log.trace("seek: to \(time) interrupted")
      }
    }
  }

  // MARK: - Setting Next Episode

  private func setNextPodcastEpisode(_ nextPodcastEpisode: PodcastEpisode?)
    async throws(PlaybackError)
  {
    guard shouldSetAsNext(nextPodcastEpisode) else { return }

    setNextEpisodeTask?.cancel()

    try await PlaybackError.catch {
      try await performSetNextEpisode(nextPodcastEpisode)
    }
  }

  private func performSetNextEpisode(_ nextPodcastEpisode: PodcastEpisode?) async throws {
    guard shouldSetAsNext(nextPodcastEpisode) else { return }

    let task = Task { [weak self] in
      guard let self else { return }
      log.debug("performSetNextPodcastEpisode: \(String(describing: nextPodcastEpisode?.toString))")

      if let podcastEpisode = nextPodcastEpisode {
        do {
          let loadedPodcastEpisode = try await loadAsset(for: podcastEpisode)
          insertNextPodcastEpisode(loadedPodcastEpisode)
        } catch {
          insertNextPodcastEpisode(nil)

          throw error
        }
      } else {
        insertNextPodcastEpisode(nil)
      }
    }

    setNextEpisodeTask = task
    defer { setNextEpisodeTask = nil }

    try await task.value
  }

  private func insertNextPodcastEpisode(_ nextLoadedPodcastEpisode: LoadedPodcastEpisode?) {
    guard shouldSetAsNext(nextLoadedPodcastEpisode?.podcastEpisode) else { return }

    log.debug("insertNextPodcastEpisode: at start:\n  \(printableQueue)")

    // If we had a second item, it needs to be removed
    if avQueuePlayer.queued.count == 2 {
      avQueuePlayer.remove(avQueuePlayer.queued[1])
    }

    // Finally, add our new item if we have one
    if let nextLoadedPodcastEpisode {
      avQueuePlayer.insert(nextLoadedPodcastEpisode.playableItem, after: avQueuePlayer.queued.first)
    }

    log.debug("insertNextPodcastEpisode: at end:\n  \(printableQueue)")

    Assert.precondition(avQueuePlayer.queued.count <= 2, "Too many AVPlayerItems?")
  }

  private func shouldSetAsNext(_ podcastEpisode: PodcastEpisode?) -> Bool {
    // If queue is empty: do nothing
    guard let lastItem = avQueuePlayer.queued.last else {
      log.trace(
        """
        shouldSetAsNext: false for \(String(describing: podcastEpisode?.toString)) \
        because queue is empty
        """
      )
      return false
    }

    // If this is already the last: do nothing
    if lastItem.assetURL == podcastEpisode?.episode.media {
      log.trace(
        """
        shouldSetAsNext: false for \(String(describing: podcastEpisode?.toString)) \
        because it already matches last item in queue:
          \(printableQueue)
        """
      )
      return false
    }

    return true
  }

  // MARK: - Change Handlers

  private func handleCurrentItemChange(_ mediaURL: MediaURL?) async throws {
    if podcastEpisode?.episode.media == mediaURL {
      log.trace(
        """
        handleCurrentItemChange: ignoring because mediaURL matches current podcastEpisode: \
        \(String(describing: mediaURL?.toString))
        """
      )
      return
    }

    if let mediaURL {
      podcastEpisode = try await repo.episode(mediaURL)
    } else {
      podcastEpisode = nil
    }

    log.debug("handleCurrentItemChange: \(String(describing: podcastEpisode?.toString))")
    currentItemContinuation.yield(podcastEpisode)
  }

  private func handleCurrentTimeChange(_ currentTime: CMTime) async throws {
    guard let podcastEpisode
    else { throw PlaybackError.settingCurrentTimeOnNil(currentTime) }

    try await repo.updateCurrentTime(podcastEpisode.id, currentTime)

    log.trace("handleCurrentTimeChange to: \(currentTime) for \(podcastEpisode.toString)")
    currentTimeContinuation.yield(currentTime)
  }

  // MARK: - Transient State Tracking

  func addObservers() {
    observeNextEpisode()
    addCurrentItemObserver()
    addPeriodicTimeObserver()
    addTimeControlStatusObserver()
  }

  func removeObservers() {
    stopObservingNextEpisode()
    removeCurrentItemObserver()
    removePeriodicTimeObserver()
    removeTimeControlStatusObserver()
  }

  private func observeNextEpisode() {
    guard observeNextEpisodeTask == nil else { return }

    observeNextEpisodeTask = Task { [weak self] in
      guard let self else { return }
      do {
        for try await nextPodcastEpisode in observatory.nextPodcastEpisode() {
          do {
            try await setNextPodcastEpisode(nextPodcastEpisode)
          } catch {
            log.error(error)
          }
        }
      } catch {
        log.error(error)
      }
    }
  }

  private func addCurrentItemObserver() {
    guard currentItemObserver == nil else { return }

    currentItemObserver = avQueuePlayer.observeCurrentItem(
      options: [.initial, .new]
    ) { [weak self] url in
      guard let self else { return }
      Task { [weak self] in
        guard let self else { return }
        do {
          try await self.handleCurrentItemChange(url)
        } catch {
          log.error(error)
        }
      }
    }
  }

  private func addPeriodicTimeObserver() {
    guard periodicTimeObserver == nil else { return }

    periodicTimeObserver = avQueuePlayer.addPeriodicTimeObserver(
      forInterval: CMTime.inSeconds(1),
      queue: .global(qos: .utility)
    ) { [weak self] currentTime in
      guard let self else { return }
      Task { [weak self] in
        guard let self else { return }
        do {
          try await self.handleCurrentTimeChange(currentTime)
        } catch {
          log.error(error)
        }
      }
    }
  }

  private func addTimeControlStatusObserver() {
    guard timeControlStatusObserver == nil else { return }

    timeControlStatusObserver = avQueuePlayer.observeTimeControlStatus(
      options: [.initial, .new]
    ) { [weak self] status in
      guard let self else { return }
      controlStatusContinuation.yield(status)
    }
  }

  private func stopObservingNextEpisode() {
    observeNextEpisodeTask?.cancel()
    observeNextEpisodeTask = nil
  }

  private func removeCurrentItemObserver() {
    if currentItemObserver != nil {
      self.currentItemObserver = nil
    }
  }

  private func removePeriodicTimeObserver() {
    if let periodicTimeObserver {
      avQueuePlayer.removeTimeObserver(periodicTimeObserver)
      self.periodicTimeObserver = nil
    }
  }

  private func removeTimeControlStatusObserver() {
    if timeControlStatusObserver != nil {
      self.timeControlStatusObserver = nil
    }
  }

  // MARK: - Debugging Helpers

  private var printableQueue: String {
    avQueuePlayer.queued.map(\.assetURL.toString).joined(separator: "\n  ")
  }
}
