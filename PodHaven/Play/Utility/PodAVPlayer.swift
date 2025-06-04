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
  @DynamicInjected(\.avQueuePlayer) var avQueuePlayer
  @DynamicInjected(\.loadEpisodeAsset) var loadEpisodeAsset
  @DynamicInjected(\.notifications) private var notifications

  private let log = Log.as(LogSubsystem.Play.avPlayer)

  // MARK: - Convenience Getters

  var podcastEpisode: PodcastEpisode? { loadedCurrentPodcastEpisode?.podcastEpisode }
  var nextPodcastEpisode: PodcastEpisode? { loadedNextPodcastEpisode?.podcastEpisode }

  // MARK: - State Management

  typealias FinishedAndLoadedCurrent = (PodcastEpisode, LoadedPodcastEpisode?)
  typealias LoadedPodcastEpisodeBundle = (
    loadedPodcastEpisode: LoadedPodcastEpisode,
    playableItem: any AVPlayableItem
  )
  private var nextBundle: LoadedPodcastEpisodeBundle?

  private var loadedNextPodcastEpisode: LoadedPodcastEpisode? { nextBundle?.loadedPodcastEpisode }
  private var loadedCurrentPodcastEpisode: LoadedPodcastEpisode?

  let currentTimeStream: AsyncStream<CMTime>
  let controlStatusStream: AsyncStream<AVPlayer.TimeControlStatus>
  let playToEndStream: AsyncStream<FinishedAndLoadedCurrent>
  private let currentTimeContinuation: AsyncStream<CMTime>.Continuation
  private let controlStatusContinuation: AsyncStream<AVPlayer.TimeControlStatus>.Continuation
  private let playToEndContinuation: AsyncStream<FinishedAndLoadedCurrent>.Continuation

  private var periodicTimeObserver: Any?
  private var timeControlStatusObserver: NSKeyValueObservation?
  private var setNextEpisodeTask: Task<Void, any Error>?

  // MARK: - Initialization

  fileprivate init() {
    (currentTimeStream, currentTimeContinuation) = AsyncStream.makeStream(
      of: CMTime.self
    )
    (controlStatusStream, controlStatusContinuation) = AsyncStream.makeStream(
      of: AVPlayer.TimeControlStatus.self
    )
    (playToEndStream, playToEndContinuation) = AsyncStream.makeStream(
      of: FinishedAndLoadedCurrent.self
    )

    addTimeControlStatusObserver()
    startPlayToEndTimeNotifications()
  }

  // MARK: - Loading

  func stop() {
    log.debug("stop: executing")
    removePeriodicTimeObserver()
    avQueuePlayer.removeAllItems()
    loadedCurrentPodcastEpisode = nil
  }

  func load(_ podcastEpisode: PodcastEpisode) async throws(PlaybackError) -> LoadedPodcastEpisode {
    log.debug("avQueuePlayer loading: \(podcastEpisode.toString)")

    let (loadedPodcastEpisode, playableItem) = try await loadAsset(for: podcastEpisode)
    loadedCurrentPodcastEpisode = loadedPodcastEpisode

    avQueuePlayer.removeAllItems()
    avQueuePlayer.insert(playableItem, after: nil)
    await insertNextPodcastEpisode(nextBundle)
    addPeriodicTimeObserver()

    return loadedPodcastEpisode
  }

  private func loadAsset(for podcastEpisode: PodcastEpisode) async throws(PlaybackError)
    -> LoadedPodcastEpisodeBundle
  {
    let episodeAsset: EpisodeAsset
    do {
      episodeAsset = try await loadEpisodeAsset(podcastEpisode.episode.media.rawValue)
    } catch {
      throw PlaybackError.loadFailure(podcastEpisode: podcastEpisode, caught: error)
    }

    guard episodeAsset.isPlayable
    else { throw PlaybackError.mediaNotPlayable(podcastEpisode) }

    return (
      LoadedPodcastEpisode(
        podcastEpisode: podcastEpisode,
        duration: episodeAsset.duration
      ),
      episodeAsset.playerItem
    )
  }

  // MARK: - Playback Controls

  func play() {
    log.debug("play: executing, playing \(String(describing: podcastEpisode?.toString))")
    avQueuePlayer.play()
  }

  func pause() {
    log.debug("pause: executing, pausing \(String(describing: podcastEpisode?.toString))")
    avQueuePlayer.pause()
  }

  // MARK: - Seeking

  func seekForward(_ duration: CMTime) {
    log.debug(
      """
      seekForward: seeking forward by \(duration) for \
      \(String(describing: podcastEpisode?.toString))
      """
    )
    seek(to: avQueuePlayer.currentTime() + duration)
  }

  func seekBackward(_ duration: CMTime) {
    log.debug(
      """
      seekForward: seeking backward by \(duration) for \
      \(String(describing: podcastEpisode?.toString))
      """
    )
    seek(to: avQueuePlayer.currentTime() - duration)
  }

  func seek(to time: CMTime) {
    log.debug(
      """
      seek: seeking to time \(time) for \
      \(String(describing: podcastEpisode?.toString))
      """
    )

    avQueuePlayer.seek(to: time) { [weak self] completed in
      guard let self else { return }

      if completed {
        log.trace("seek to \(time) completed")
      } else {
        log.trace("seek to \(time) interrupted")
      }
    }
  }

  // MARK: - State Setters

  func setNextPodcastEpisode(_ nextPodcastEpisode: PodcastEpisode?) async throws(PlaybackError) {
    setNextEpisodeTask?.cancel()

    try await PlaybackError.catch {
      try await performSetNextEpisode(nextPodcastEpisode)
    }
  }

  private func performSetNextEpisode(_ nextPodcastEpisode: PodcastEpisode?) async throws {
    let task = Task {
      log.debug("setNextPodcastEpisode: \(String(describing: nextPodcastEpisode?.toString))")

      guard nextPodcastEpisode?.id != self.nextPodcastEpisode?.id
      else {
        log.warning(
          """
          setNextPodcastEpisode: Trying to set next episode to \
          \(String(describing: nextPodcastEpisode?.toString)) \
          but it is the same as the current next episode
          """
        )
        return
      }

      if let podcastEpisode = nextPodcastEpisode {
        do {
          let loadedPodcastEpisodeBundle = try await loadAsset(for: podcastEpisode)
          await insertNextPodcastEpisode(loadedPodcastEpisodeBundle)
        } catch {
          log.notice(ErrorKit.loggableMessage(for: error))
          await insertNextPodcastEpisode(nil)

          throw error
        }
      } else {
        await insertNextPodcastEpisode(nil)
      }
    }

    setNextEpisodeTask = task
    defer { setNextEpisodeTask = nil }

    try await task.value
  }

  // MARK: - Private State Management

  private func insertNextPodcastEpisode(_ nextBundle: LoadedPodcastEpisodeBundle?) async {
    log.debug(
      "insertNextPodcastEpisode: \(String(describing: nextBundle?.loadedPodcastEpisode.toString))"
    )

    if log.wouldLog(.debug) {
      let queuedPodcastEpisodes = await queuedPodcastEpisodes()
      log.debug(
        """
        insertNextPodcastEpisode: AVPlayer assets at start of function are:
          \(queuedPodcastEpisodes.map(\.toString).joined(separator: "\n  "))
        """
      )
    }

    performInsertNextPodcastEpisode(nextBundle)

    if log.wouldLog(.debug) {
      let queuedPodcastEpisodes = await queuedPodcastEpisodes()
      log.debug(
        """
        insertNextPodcastEpisode: AVPlayer assets at end of function are:
          \(queuedPodcastEpisodes.map(\.toString).joined(separator: "\n  "))
        """
      )
    }
  }

  private func performInsertNextPodcastEpisode(_ nextBundle: LoadedPodcastEpisodeBundle?) {
    self.nextBundle = nextBundle

    if avQueuePlayer.items().isEmpty { return }

    if avQueuePlayer.items().count == 1 && loadedNextPodcastEpisode == nil { return }

    if avQueuePlayer.items().count == 2,
      avQueuePlayer.items().last?.assetURL == loadedNextPodcastEpisode?.assetURL
    {
      return
    }

    while avQueuePlayer.items().count > 1, let lastItem = avQueuePlayer.items().last {
      avQueuePlayer.remove(lastItem)
    }

    if let nextBundle = self.nextBundle {
      avQueuePlayer.insert(nextBundle.playableItem, after: avQueuePlayer.items().first)
    }
  }

  // MARK: - Private Change Handlers

  private func handleEpisodeFinished() throws(PlaybackError) {
    guard let finishedPodcastEpisode = podcastEpisode
    else { Assert.fatal("Finished episode but current episode is nil?") }

    log.debug("handleEpisodeFinished: Episode finished: \(finishedPodcastEpisode.toString)")

    loadedCurrentPodcastEpisode = loadedNextPodcastEpisode
    nextBundle = nil
    playToEndContinuation.yield((finishedPodcastEpisode, loadedCurrentPodcastEpisode))
  }

  // MARK: - Private Tracking

  private func addPeriodicTimeObserver() {
    guard periodicTimeObserver == nil
    else { return }

    log.debug("addPeriodicTimeObserver: Adding periodic time observer")
    periodicTimeObserver = avQueuePlayer.addPeriodicTimeObserver(
      forInterval: CMTime.inSeconds(1),
      queue: .global(qos: .utility)
    ) { [weak self] currentTime in
      guard let self else { return }
      currentTimeContinuation.yield(currentTime)
    }
  }

  private func removePeriodicTimeObserver() {
    if let periodicTimeObserver {
      log.debug("removePeriodicTimeObserver: Removing periodic time observer")
      avQueuePlayer.removeTimeObserver(periodicTimeObserver)
      self.periodicTimeObserver = nil
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
      for await _ in notifications(AVPlayerItem.didPlayToEndTimeNotification) {
        try? handleEpisodeFinished()
      }
    }
  }

  // MARK: - Debug Helpers

  private func queuedPodcastEpisodes() async -> [PodcastEpisode] {
    let mediaURLs = avQueuePlayer.items().map { MediaURL($0.assetURL) }
    let podcastEpisodes = IdentifiedArray(
      uniqueElements: (try? await Container.shared.repo().episodes(mediaURLs)) ?? [],
      id: \.episode.media
    )
    var podcastEpisodesFound = [PodcastEpisode](capacity: mediaURLs.count)
    var mediaURLsNotFound: [MediaURL] = []
    for mediaURL in mediaURLs {
      if let podcastEpisode = podcastEpisodes[id: mediaURL] {
        podcastEpisodesFound.append(podcastEpisode)
      } else {
        mediaURLsNotFound.append(mediaURL)
      }
    }
    Assert.precondition(
      mediaURLsNotFound.isEmpty,
      """
      \(mediaURLs.count) media URLs but \(podcastEpisodes.count) podcast episodes)
      MediaURLsNotFound:
        \(mediaURLsNotFound.map({ "\($0)" }).joined(separator: "\n  "))
      PodcastEpisodesFound: 
        \(podcastEpisodesFound.map(\.toString).joined(separator: "\n  "))
      LoadedCurrentPodcastEpisode:
        \(String(describing: loadedCurrentPodcastEpisode?.toString))
        MediaURL: \(String(describing:
                loadedCurrentPodcastEpisode?.podcastEpisode.episode.media))
      LoadedNextPodcastEpisode:
        \(String(describing: loadedNextPodcastEpisode?.toString))
        MediaURL: \(String(describing:
                loadedNextPodcastEpisode?.podcastEpisode.episode.media))
      """
    )

    return podcastEpisodesFound
  }
}
