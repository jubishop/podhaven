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
  @DynamicInjected(\.avQueuePlayer) private var avQueuePlayer
  @DynamicInjected(\.loadEpisodeAsset) private var loadEpisodeAsset
  @DynamicInjected(\.notifications) private var notifications
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.repo) private var repo

  nonisolated private static let log = Log.as(LogSubsystem.Play.avPlayer)

  // MARK: - State Management

  typealias LoadedPodcastEpisode = (
    podcastEpisode: PodcastEpisode,
    playableItem: any AVPlayableItem
  )
  private var podcastEpisode: PodcastEpisode?
  private var preSeekStatus: PlaybackStatus?

  let currentTimeStream: AsyncStream<CMTime>
  let currentItemStream: AsyncStream<PodcastEpisode?>
  let itemStatusStream: AsyncStream<(status: AVPlayerItem.Status, episodeID: Episode.ID?)>
  let controlStatusStream: AsyncStream<PlaybackStatus>
  let rateStream: AsyncStream<Float>

  private let currentTimeContinuation: AsyncStream<CMTime>.Continuation
  private let currentItemContinuation: AsyncStream<PodcastEpisode?>.Continuation
  private let itemStatusContinuation:
    AsyncStream<(status: AVPlayerItem.Status, episodeID: Episode.ID?)>.Continuation
  private let controlStatusContinuation: AsyncStream<PlaybackStatus>.Continuation
  private let rateContinuation: AsyncStream<Float>.Continuation

  private var periodicTimeObserver: Any?
  private var currentItemObserver: NSKeyValueObservation?
  private var itemStatusObserver: NSKeyValueObservation?
  private var timeControlStatusObserver: NSKeyValueObservation?
  private var rateObserver: NSKeyValueObservation?

  private var observeNextEpisodeTask: Task<Void, Never>?
  private var setNextEpisodeTask: Task<Void, any Error>?

  // MARK: - Initialization

  fileprivate init() {
    (currentTimeStream, currentTimeContinuation) = AsyncStream.makeStream(of: CMTime.self)
    (currentItemStream, currentItemContinuation) = AsyncStream.makeStream(of: PodcastEpisode?.self)
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
    preSeekStatus = nil
    avQueuePlayer.removeAllItems()
  }

  // MARK: - Playback Controls

  func play() {
    Self.log.debug("play: executing")
    preSeekStatus = .playing
    avQueuePlayer.play()
  }

  func pause(overwritePreSeekStatus: Bool = true) {
    Self.log.debug("pause: executing")
    if overwritePreSeekStatus {
      preSeekStatus = .paused
    }
    avQueuePlayer.pause()
  }

  func toggle() {
    let currentStatus = avQueuePlayer.timeControlStatus
    Self.log.debug("toggle: executing (current status: \(currentStatus))")
    currentStatus == .paused
      ? play()
      : pause()
  }

  // MARK: - Seeking

  func seekForward(_ duration: CMTime) {
    Self.log.debug("seekForward: \(duration)")
    seek(to: avQueuePlayer.currentTime() + duration)
  }

  func seekBackward(_ duration: CMTime) {
    Self.log.debug("seekBackward: \(duration)")
    seek(to: avQueuePlayer.currentTime() - duration)
  }

  func seek(to time: CMTime) {
    Self.log.debug("seek: \(time)")

    removePeriodicTimeObserver()
    currentTimeContinuation.yield(time)
    preSeekStatus = preSeekStatus ?? PlaybackStatus(avQueuePlayer.timeControlStatus)
    pause(overwritePreSeekStatus: false)
    controlStatusContinuation.yield(.seeking)

    avQueuePlayer.seek(to: time) { [weak self] completed in
      guard let self else { return }

      if completed {
        Self.log.debug("seek: to \(time) completed")
        Task { @MainActor [weak self] in
          guard let self else { return }
          if let preSeekStatus {
            self.preSeekStatus = nil
            if preSeekStatus != .paused {
              play()
            } else {
              controlStatusContinuation.yield(.paused)
            }
          }
          addPeriodicTimeObserver()
        }
      } else {
        Self.log.debug("seek: to \(time) interrupted")
      }
    }
  }

  // MARK: - Setting Next Episode

  private func setNextPodcastEpisode(_ nextPodcastEpisode: PodcastEpisode?)
    async throws(PlaybackError)
  {
    setNextEpisodeTask?.cancel()

    try await PlaybackError.catch {
      try await performSetNextEpisode(nextPodcastEpisode)
    }
  }

  private func performSetNextEpisode(_ nextPodcastEpisode: PodcastEpisode?) async throws {
    guard shouldSetAsNext(nextPodcastEpisode) else { return }

    let task = Task { [weak self] in
      guard let self else { return }
      Self.log.debug(
        "performSetNextPodcastEpisode: \(String(describing: nextPodcastEpisode?.toString))"
      )

      if let podcastEpisode = nextPodcastEpisode {
        do {
          await insertNextPodcastEpisode(try await loadAsset(for: podcastEpisode))
        } catch {
          await insertNextPodcastEpisode(nil)

          throw error
        }
      } else {
        await insertNextPodcastEpisode(nil)
      }
    }

    setNextEpisodeTask = task
    try await task.value
  }

  private func insertNextPodcastEpisode(_ nextLoadedPodcastEpisode: LoadedPodcastEpisode?) async {
    guard shouldSetAsNext(nextLoadedPodcastEpisode?.podcastEpisode) else { return }

    Self.log.debug("insertNextPodcastEpisode: at start:\n  \(printableQueue)")

    // If we had a second item, it needs to be removed
    if avQueuePlayer.queued.count == 2 {
      avQueuePlayer.remove(avQueuePlayer.queued[1])
    }

    // Finally, add our new item if we have one
    if let nextLoadedPodcastEpisode {
      let imageFetcher = Container.shared.imageFetcher()
      await imageFetcher.prefetch([nextLoadedPodcastEpisode.podcastEpisode.image])
      avQueuePlayer.insert(nextLoadedPodcastEpisode.playableItem, after: avQueuePlayer.queued.first)
    }

    Self.log.debug("insertNextPodcastEpisode: at end:\n  \(printableQueue)")

    Assert.precondition(avQueuePlayer.queued.count <= 2, "Too many AVPlayerItems?")
  }

  private func shouldSetAsNext(_ podcastEpisode: PodcastEpisode?) -> Bool {
    // If queue is empty: do nothing
    guard let lastItem = avQueuePlayer.queued.last else {
      Self.log.debug(
        """
        shouldSetAsNext: false for \(String(describing: podcastEpisode?.toString)) \
        because queue is empty
        """
      )
      return false
    }

    // If this is already the last: do nothing
    if lastItem.episodeID == podcastEpisode?.episode.id {
      Self.log.debug(
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

  private func handleCurrentItemChange(_ currentItem: (any AVPlayableItem)?) async throws {
    let episodeID = currentItem?.episodeID

    if podcastEpisode?.episode.id == episodeID {
      Self.log.debug(
        """
        handleCurrentItemChange: ignoring because id matches current podcastEpisode: \
        \(String(describing: podcastEpisode?.toString))
        """
      )
      return
    }

    if let currentItem {
      addItemStatusObserver(playableItem: currentItem)
    } else {
      removeItemStatusObserver()
    }

    if let episodeID {
      podcastEpisode = try await repo.episode(episodeID)
    } else {
      podcastEpisode = nil
    }

    Self.log.debug("handleCurrentItemChange: \(String(describing: podcastEpisode?.toString))")
    currentItemContinuation.yield(podcastEpisode)
  }

  private func handleCurrentTimeChange(_ currentTime: CMTime) async throws {
    guard let podcastEpisode
    else { throw PlaybackError.settingCurrentTimeOnNil(currentTime) }

    try await repo.updateCurrentTime(podcastEpisode.id, currentTime)

    Self.log.trace("handleCurrentTimeChange to: \(currentTime) for \(podcastEpisode.toString)")
    currentTimeContinuation.yield(currentTime)
  }

  // MARK: - Transient State Tracking

  func addObservers() {
    observeNextEpisode()
    addCurrentItemObserver()
    addPeriodicTimeObserver()
    addTimeControlStatusObserver()
    addRateObserver()
  }

  func removeObservers() {
    stopObservingNextEpisode()
    removeCurrentItemObserver()
    removeItemStatusObserver()
    removePeriodicTimeObserver()
    removeTimeControlStatusObserver()
    removeRateObserver()
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
            Self.log.error(error)
          }
        }
      } catch {
        Self.log.error(error)
      }
    }
  }

  private func addCurrentItemObserver() {
    guard currentItemObserver == nil else { return }

    currentItemObserver = avQueuePlayer.observeCurrentItem(
      options: [.initial, .new]
    ) { @MainActor [weak self] currentItem in
      guard let self else { return }

      Task { [weak self] in
        guard let self else { return }
        do {
          try await self.handleCurrentItemChange(currentItem)
        } catch {
          Self.log.error(error)
        }
      }
    }
  }

  private func addItemStatusObserver(playableItem: any AVPlayableItem) {
    removeItemStatusObserver()

    let episodeID = playableItem.episodeID
    itemStatusObserver = playableItem.observeStatus(options: [.initial, .new]) {
      [weak self] status in
      guard let self else { return }
      itemStatusContinuation.yield((status: status, episodeID: episodeID))
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
          Self.log.error(error)
        }
      }
    }
  }

  private func addTimeControlStatusObserver() {
    guard timeControlStatusObserver == nil else { return }

    timeControlStatusObserver = avQueuePlayer.observeTimeControlStatus(options: [.initial, .new]) {
      [weak self] status in
      guard let self else { return }
      controlStatusContinuation.yield(PlaybackStatus(status))
    }
  }

  private func addRateObserver() {
    guard rateObserver == nil else { return }

    rateObserver = avQueuePlayer.observeRate(options: [.initial, .new]) { [weak self] rate in
      guard let self else { return }
      rateContinuation.yield(rate)
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

  private func removeItemStatusObserver() {
    if itemStatusObserver != nil {
      self.itemStatusObserver = nil
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

  private func removeRateObserver() {
    if rateObserver != nil {
      self.rateObserver = nil
    }
  }

  // MARK: - Debugging Helpers

  private var printableQueue: String {
    avQueuePlayer.queued.map { String(describing: $0.episodeID) }.joined(separator: "\n  ")
  }
}
