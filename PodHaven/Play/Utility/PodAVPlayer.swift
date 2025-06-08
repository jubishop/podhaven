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
  private var transitionStatus: AVPlayer.TimeControlStatus?

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
    startPlayToEndTimeNotifications()
  }

  // MARK: - Loading

  func stop() {
    log.debug("stop: executing")
    removeTransientObservers()
    self.podcastEpisode = nil
    self.transitionStatus = nil
    avQueuePlayer.removeAllItems()
  }

  func load(_ podcastEpisode: PodcastEpisode) async throws(PlaybackError) -> PodcastEpisode {
    log.debug("load: \(podcastEpisode.toString)")

    let (podcastEpisode, playableItem) = try await loadAsset(for: podcastEpisode)
    avQueuePlayer.removeAllItems()
    avQueuePlayer.insert(playableItem, after: nil)
    self.transitionStatus = nil
    self.podcastEpisode = podcastEpisode

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
      if ErrorKit.isRemarkable(error) {
        log.error(ErrorKit.loggableMessage(for: error))
      }
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

  func cacheStatusAndPause() {
    transitionStatus = transitionStatus ?? avQueuePlayer.timeControlStatus
    pause()
  }

  func clearStatusAndMaybePlay() {
    if let transitionStatus {
      self.transitionStatus = nil
      if transitionStatus != .paused { play() }
    }
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
    cacheStatusAndPause()

    avQueuePlayer.seek(to: time) { [weak self] completed in
      guard let self else { return }

      if completed {
        log.trace("seek: to \(time) completed")
        Task { @MainActor in
          clearStatusAndMaybePlay()
          addPeriodicTimeObserver()
        }
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
          if ErrorKit.isRemarkable(error) {
            log.error(ErrorKit.loggableMessage(for: error))
          }
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
        \(avQueuePlayer.queued.map {
          "\($0.assetURL.rawValue.absoluteString.hashToCharacters(3))"
          }.joined(separator: "\n  "))
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
        \(avQueuePlayer.queued.map {
          "\($0.assetURL.rawValue.absoluteString.hashToCharacters(3))"
          }.joined(separator: "\n  "))
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

  private func handleItemDidPlayToEndTime(_ mediaURL: MediaURL?) async throws {

  }

  // MARK: - Transient Tracking

  func addTransientObservers() {
    addCurrentItemObserver()
    addPeriodicTimeObserver()
  }

  func removeTransientObservers() {
    removeCurrentItemObserver()
    removePeriodicTimeObserver()
  }

  private func addCurrentItemObserver() {
    guard currentItemObserver == nil else { return }

    currentItemObserver = avQueuePlayer.observeCurrentItem(
      options: [.initial, .new]
    ) { url in
      self.log.info("current item changed")
      Task {
        do {
          try await self.handleCurrentItemChange(url)
        } catch {
          if ErrorKit.isRemarkable(error) {
            self.log.error(ErrorKit.loggableMessage(for: error))
          }
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
      currentTimeContinuation.yield(currentTime)
    }
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

  // MARK: - Private State Tracking

  private func observeNextEpisode() {
    Assert.neverCalled()

    Task {
      do {
        for try await nextPodcastEpisode in observatory.nextPodcastEpisode() {
          do {
            try await setNextPodcastEpisode(nextPodcastEpisode)
          } catch {
            if ErrorKit.isRemarkable(error) {
              log.error(ErrorKit.loggableMessage(for: error))
            }
          }
        }
      } catch {
        if ErrorKit.isRemarkable(error) {
          log.error(ErrorKit.loggableMessage(for: error))
        }
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

  private func startPlayToEndTimeNotifications() {
    Assert.neverCalled()

    Task {
      for await notification in notifications(AVPlayerItem.didPlayToEndTimeNotification) {
        log.info("didPlayToEndTimeNotification")
        guard let playerItem = notification.object as? AVPlayerItem
        else { Assert.fatal("didPlayToEndTimeNotification: object is not an AVPlayerItem") }
        do {
          try await handleItemDidPlayToEndTime(playerItem.assetURL)
        } catch {
          if ErrorKit.isRemarkable(error) {
            log.error(ErrorKit.loggableMessage(for: error))
          }
        }
      }
    }
  }
}
