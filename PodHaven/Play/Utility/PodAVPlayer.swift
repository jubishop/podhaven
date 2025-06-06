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

  var loadEpisodeAsset: Factory<(_ url: URL) async throws -> EpisodeAsset> {
    Factory(self) {
      { url in
        let asset = AVURLAsset(url: url)
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
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.repo) private var repo

  private let log = Log.as(LogSubsystem.Play.avPlayer)

  // MARK: - State Management

  typealias LoadedPodcastEpisode = (
    podcastEpisode: PodcastEpisode,
    playableItem: any AVPlayableItem
  )
  private(set) var podcastEpisode: PodcastEpisode?

  let currentTimeStream: AsyncStream<CMTime>
  let currentItemStream: AsyncStream<PodcastEpisode?>
  let controlStatusStream: AsyncStream<AVPlayer.TimeControlStatus>
  private let currentTimeContinuation: AsyncStream<CMTime>.Continuation
  private let currentItemContinuation: AsyncStream<PodcastEpisode?>.Continuation
  private let controlStatusContinuation: AsyncStream<AVPlayer.TimeControlStatus>.Continuation

  private var periodicTimeObserver: Any?
  private var currentItemObserver: NSKeyValueObservation?
  private var timeControlStatusObserver: NSKeyValueObservation?
  private var setNextEpisodeTask: Task<Void, any Error>?

  // MARK: - Initialization

  fileprivate init() {
    (currentTimeStream, currentTimeContinuation) = AsyncStream.makeStream(of: CMTime.self)
    (currentItemStream, currentItemContinuation) = AsyncStream.makeStream(of: PodcastEpisode?.self)
    (controlStatusStream, controlStatusContinuation) = AsyncStream.makeStream(
      of: AVPlayer.TimeControlStatus.self
    )

    observeNextEpisode()
    addTimeControlStatusObserver()
  }

  // MARK: - Loading

  func stop() {
    log.debug("stop: executing")
    removeTransientObservers()
    avQueuePlayer.removeAllItems()
  }

  func load(_ podcastEpisode: PodcastEpisode) async throws(PlaybackError) -> PodcastEpisode {
    log.debug("load: \(podcastEpisode.toString)")

    removeTransientObservers()
    let (podcastEpisode, playableItem) = try await loadAsset(for: podcastEpisode)

    avQueuePlayer.removeAllItems()
    avQueuePlayer.insert(playableItem, after: nil)
    self.podcastEpisode = podcastEpisode
    addTransientObservers()

    return podcastEpisode
  }

  private func loadAsset(for podcastEpisode: PodcastEpisode) async throws(PlaybackError)
    -> LoadedPodcastEpisode
  {
    log.debug("loadAsset: \(podcastEpisode.toString)")

    let episodeAsset: EpisodeAsset
    do {
      episodeAsset = try await loadEpisodeAsset(podcastEpisode.episode.media.rawValue)
    } catch {
      log.warning("loadAsset: failed to load asset for \(podcastEpisode.toString)")
      throw PlaybackError.loadFailure(podcastEpisode: podcastEpisode, caught: error)
    }

    guard episodeAsset.isPlayable
    else { throw PlaybackError.mediaNotPlayable(podcastEpisode) }

    var episode = podcastEpisode.episode
    episode.duration = episodeAsset.duration
    _ = try? await repo.updateDuration(podcastEpisode.id, episode.duration)

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
    avQueuePlayer.play()
  }

  func pause() {
    log.debug("pausing")
    avQueuePlayer.pause()
  }

  func toggle() {
    avQueuePlayer.timeControlStatus == .paused
      ? play()
      : pause()
  }

  // MARK: - Seeking

  func seekForward(_ duration: CMTime) {
    log.debug("seekForward: \(duration)")
    seek(to: avQueuePlayer.currentTime() + duration)
  }

  func seekBackward(_ duration: CMTime) {
    log.debug("seekBackward: \(duration)")
    seek(to: avQueuePlayer.currentTime() - duration)
  }

  func seek(to time: CMTime) {
    log.debug("seek: \(time)")
    avQueuePlayer.seek(to: time) { [weak self] completed in
      guard let self else { return }

      if completed {
        log.trace("seek: to \(time) completed")
      } else {
        log.trace("seek: to \(time) interrupted")
      }
    }
  }

  // MARK: - Setting Next Episode

  func setNextPodcastEpisode(_ nextPodcastEpisode: PodcastEpisode?) async throws(PlaybackError) {
    setNextEpisodeTask?.cancel()

    try await PlaybackError.catch {
      try await performSetNextEpisode(nextPodcastEpisode)
    }
  }

  private func performSetNextEpisode(_ nextPodcastEpisode: PodcastEpisode?) async throws {
    guard shouldSetAsNext(nextPodcastEpisode) else { return }

    let task = Task {
      log.debug("performSetNextPodcastEpisode: \(String(describing: nextPodcastEpisode?.toString))")

      if let podcastEpisode = nextPodcastEpisode {
        do {
          let loadedPodcastEpisode = try await loadAsset(for: podcastEpisode)
          insertNextPodcastEpisode(loadedPodcastEpisode)
        } catch {
          log.error(ErrorKit.loggableMessage(for: error))
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

    log.debug(
      """
      insertNextPodcastEpisode: at start:
        \(avQueuePlayer.queued.map { "\($0.assetURL)" }.joined(separator: "\n  "))
      """
    )

    // If we had a second item, it needs to be removed
    if avQueuePlayer.queued.count == 2 {
      avQueuePlayer.remove(avQueuePlayer.queued[1])
    }

    // Finally, add our new item if we have one
    if let nextLoadedPodcastEpisode {
      avQueuePlayer.insert(nextLoadedPodcastEpisode.playableItem, after: avQueuePlayer.queued.first)
    }

    log.debug(
      """
      insertNextPodcastEpisode: at end:
        \(avQueuePlayer.queued.map { "\($0.assetURL)" }.joined(separator: "\n  "))
      """
    )

    Assert.precondition(avQueuePlayer.queued.count <= 2, "Too many AVPlayerItems?")
  }

  private func shouldSetAsNext(_ podcastEpisode: PodcastEpisode?) -> Bool {
    // If queue is empty: do nothing
    guard let lastItem = avQueuePlayer.queued.last else { return false }

    // If this is already the last: do nothing
    if lastItem.assetURL == podcastEpisode?.episode.media { return false }

    return true
  }

  // MARK: - Private Change Handlers

  private func handleCurrentItemChange(_ mediaURL: MediaURL?) async throws {
    if podcastEpisode?.episode.media == mediaURL { return }

    if let mediaURL {
      podcastEpisode = try await repo.episode(mediaURL)
    } else {
      podcastEpisode = nil
    }

    log.debug("handleCurrentItemChange: \(String(describing: podcastEpisode))")
    currentItemContinuation.yield(podcastEpisode)
  }

  // MARK: - Private Transient Tracking

  private func addTransientObservers() {
    if currentItemObserver == nil {
      currentItemObserver = avQueuePlayer.observeCurrentItem(
        options: [.initial, .new]
      ) { url in
        Task { try await self.handleCurrentItemChange(url) }
      }
    }

    if periodicTimeObserver == nil {
      periodicTimeObserver = avQueuePlayer.addPeriodicTimeObserver(
        forInterval: CMTime.inSeconds(1),
        queue: .global(qos: .utility)
      ) { [weak self] currentTime in
        guard let self else { return }
        currentTimeContinuation.yield(currentTime)
      }
    }
  }

  private func removeTransientObservers() {
    if let periodicTimeObserver {
      avQueuePlayer.removeTimeObserver(periodicTimeObserver)
      self.periodicTimeObserver = nil
    }

    if currentItemObserver != nil {
      self.currentItemObserver = nil
    }
  }

  // MARK: - Private State Tracking

  private func observeNextEpisode() {
    Assert.neverCalled()

    Task {
      do {
        for try await nextPodcastEpisode in observatory.nextPodcastEpisode() {
          try? await setNextPodcastEpisode(nextPodcastEpisode)
        }
      } catch {
        log.error(ErrorKit.loggableMessage(for: error))
      }
    }
  }

  private func addTimeControlStatusObserver() {
    Assert.neverCalled()

    timeControlStatusObserver = avQueuePlayer.observeTimeControlStatus(
      options: [.initial, .new]
    ) { status in
      self.controlStatusContinuation.yield(status)
    }
  }
}
