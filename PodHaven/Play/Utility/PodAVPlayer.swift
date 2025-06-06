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

  typealias LoadedPodcastEpisodeBundle = (
    loadedPodcastEpisode: LoadedPodcastEpisode,
    playableItem: any AVPlayableItem
  )
  var podcastEpisode: PodcastEpisode?

  let currentTimeStream: AsyncStream<CMTime>
  let currentItemStream: AsyncStream<Void>
  let controlStatusStream: AsyncStream<AVPlayer.TimeControlStatus>
  private let currentTimeContinuation: AsyncStream<CMTime>.Continuation
  private let currentItemContinuation: AsyncStream<Void>.Continuation
  private let controlStatusContinuation: AsyncStream<AVPlayer.TimeControlStatus>.Continuation

  private var periodicTimeObserver: Any?
  private var currentItemObserver: NSKeyValueObservation?
  private var timeControlStatusObserver: NSKeyValueObservation?
  private var setNextEpisodeTask: Task<Void, any Error>?

  // MARK: - Initialization

  fileprivate init() {
    (currentTimeStream, currentTimeContinuation) = AsyncStream.makeStream(
      of: CMTime.self
    )
    (currentItemStream, currentItemContinuation) = AsyncStream.makeStream(
      of: Void.self
    )
    (controlStatusStream, controlStatusContinuation) = AsyncStream.makeStream(
      of: AVPlayer.TimeControlStatus.self
    )

    observeNextEpisode()
    addTimeControlStatusObserver()
    addCurrentItemObserver()
  }

  // MARK: - Loading

  func stop() {
    log.debug("stop: executing")
    removePeriodicTimeObserver()
    avQueuePlayer.removeAllItems()
  }

  func load(_ podcastEpisode: PodcastEpisode) async throws(PlaybackError) -> LoadedPodcastEpisode {
    log.debug("load: \(podcastEpisode.toString)")

    removePeriodicTimeObserver()
    let (loadedPodcastEpisode, playableItem) = try await loadAsset(for: podcastEpisode)

    avQueuePlayer.removeAllItems()
    avQueuePlayer.insert(playableItem, after: nil)
    addPeriodicTimeObserver()

    return loadedPodcastEpisode
  }

  private func loadAsset(for podcastEpisode: PodcastEpisode) async throws(PlaybackError)
    -> LoadedPodcastEpisodeBundle
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

    _ = try? await repo.updateDuration(podcastEpisode.id, episodeAsset.duration)

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
    log.debug("playing")
    avQueuePlayer.play()
  }

  func pause() {
    log.debug("pausing")
    avQueuePlayer.pause()
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
    let task = Task {
      log.debug("performSetNextPodcastEpisode: \(String(describing: nextPodcastEpisode?.toString))")

      if let podcastEpisode = nextPodcastEpisode {
        do {
          let loadedPodcastEpisodeBundle = try await loadAsset(for: podcastEpisode)
          insertNextPodcastEpisode(loadedPodcastEpisodeBundle)
        } catch {
          log.notice(ErrorKit.loggableMessage(for: error))
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

  private func insertNextPodcastEpisode(_ nextBundle: LoadedPodcastEpisodeBundle?) {
    log.debug(
      "insertNextPodcastEpisode: \(String(describing: nextBundle?.loadedPodcastEpisode.toString))"
    )

    if log.wouldLog(.debug) {
      Task {
        let queuedPodcastEpisodes = await queuedPodcastEpisodes()
        log.debug(
          """
          insertNextPodcastEpisode: at start:
            \(queuedPodcastEpisodes.map(\.toString).joined(separator: "\n  "))
          """
        )
      }
    }

    performInsertNextPodcastEpisode(nextBundle)

    if log.wouldLog(.debug) {
      Task {
        let queuedPodcastEpisodes = await queuedPodcastEpisodes()
        log.debug(
          """
          insertNextPodcastEpisode: at end:
            \(queuedPodcastEpisodes.map(\.toString).joined(separator: "\n  "))
          """
        )
      }
    }

    Assert.precondition(avQueuePlayer.queued.count <= 2, "Too many AVPlayerItems?")
  }

  private func performInsertNextPodcastEpisode(_ nextBundle: LoadedPodcastEpisodeBundle?) {
    // If queue is empty: do nothing
    guard let lastItem = avQueuePlayer.queued.last else { return }

    // If this is already the last: do nothing
    if lastItem.assetURL == nextBundle?.loadedPodcastEpisode.assetURL { return }

    // If we had a second item, it needs to be removed
    if avQueuePlayer.queued.count > 1 {
      avQueuePlayer.remove(lastItem)
    }

    // Finally, add our new item if we have one
    if let nextBundle {
      avQueuePlayer.insert(nextBundle.playableItem, after: avQueuePlayer.queued.first)
    }
  }

  // MARK: - Private Change Handlers

  private func handleCurrentItemChange(_ url: URL?) async throws {
    if let url {
      podcastEpisode = try await repo.episode(MediaURL(url))
    } else {
      podcastEpisode = nil
    }
    log.debug("handleCurrentItemChange: \(String(describing: podcastEpisode))")
    currentItemContinuation.yield()
  }

  // MARK: - Private Tracking

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

  private func addPeriodicTimeObserver() {
    guard periodicTimeObserver == nil
    else { return }

    log.debug("addPeriodicTimeObserver: executing")
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
      log.debug("removePeriodicTimeObserver: executing")
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

  private func addCurrentItemObserver() {
    Assert.neverCalled()

    currentItemObserver = avQueuePlayer.observeCurrentItem(
      options: [.initial, .new]
    ) { url in
      Task { try await self.handleCurrentItemChange(url) }
    }
  }

  // MARK: - Debug Helpers

  private func queuedPodcastEpisodes() async -> [PodcastEpisode] {
    let mediaURLs = avQueuePlayer.queued.map { MediaURL($0.assetURL) }
    var podcastEpisodes: IdentifiedArray<MediaURL, PodcastEpisode>
    do {
      podcastEpisodes = IdentifiedArray(
        uniqueElements: try await Container.shared.repo().episodes(mediaURLs),
        id: \.episode.media
      )
    } catch {
      log.warning(ErrorKit.loggableMessage(for: error))
      podcastEpisodes = IdentifiedArray(id: \.episode.media)
    }
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
      PodcastEpisodes fetched: 
        \(podcastEpisodes.map(\.toString).joined(separator: "\n  "))
      MediaURLsNotFound:
        \(mediaURLsNotFound.map({ "\($0)" }).joined(separator: "\n  "))
      PodcastEpisodesFound: 
        \(podcastEpisodesFound.map(\.toString).joined(separator: "\n  "))
      """
    )

    return podcastEpisodesFound
  }
}
