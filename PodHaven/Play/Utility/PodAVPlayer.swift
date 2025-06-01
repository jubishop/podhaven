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
          duration: duration,
          isPlayable: isPlayable
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

  // MARK: - Debugging

  private let logSemaphor = AsyncSemaphore(value: 1)

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

  private var timeControlStatusObserver: NSKeyValueObservation?
  private var periodicTimeObserver: Any?
  private var playToEndNotificationTask: Task<Void, Never>?

  // MARK: - Initialization

  fileprivate init() {
    (self.currentTimeStream, self.currentTimeContinuation) = AsyncStream.makeStream(
      of: CMTime.self
    )
    (self.controlStatusStream, self.controlStatusContinuation) = AsyncStream.makeStream(
      of: AVPlayer.TimeControlStatus.self
    )
    (self.playToEndStream, self.playToEndContinuation) = AsyncStream.makeStream(
      of: FinishedAndLoadedCurrent.self
    )

    addPeriodicTimeObserver()
    addTimeControlStatusObserver()
    startPlayToEndTimeNotifications()
  }

  // MARK: - Loading

  func stop() {
    log.debug("stop: executing")
    removePeriodicTimeObserver()
    avQueuePlayer.removeAllItems()
    self.loadedCurrentPodcastEpisode = nil
  }

  func load(_ podcastEpisode: PodcastEpisode) async throws(PlaybackError) -> LoadedPodcastEpisode {
    log.debug("avQueuePlayer loading: \(podcastEpisode.toString)")

    let (loadedPodcastEpisode, playableItem) = try await loadAsset(for: podcastEpisode)
    self.loadedCurrentPodcastEpisode = loadedPodcastEpisode

    avQueuePlayer.removeAllItems()
    avQueuePlayer.insert(playableItem, after: nil)
    insertNextPodcastEpisode(nextBundle)
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
    removePeriodicTimeObserver()
    currentTimeContinuation.yield(time)
    avQueuePlayer.seek(to: time) { [weak self] completed in
      guard let self else { return }

      if completed {
        self.log.debug("seek completed")
        Task { await self.addPeriodicTimeObserver() }
      } else {
        self.log.debug("seek interrupted")
      }
    }
  }

  // MARK: - State Setters

  func setNextPodcastEpisode(_ nextPodcastEpisode: PodcastEpisode?) async {
    log.debug("setNextPodcastEpisode: \(String(describing: nextPodcastEpisode?.toString))")

    guard nextPodcastEpisode?.id != self.nextPodcastEpisode?.id
    else {
      log.info(
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
        insertNextPodcastEpisode(try await loadAsset(for: podcastEpisode))
      } catch {
        log.error(ErrorKit.loggableMessage(for: error))
        insertNextPodcastEpisode(nil)
      }
    } else {
      insertNextPodcastEpisode(nil)
    }
  }

  // MARK: - Private State Management

  private func insertNextPodcastEpisode(_ nextBundle: LoadedPodcastEpisodeBundle?) {
    defer {
      if log.wouldLog(.debug) {
        Task(priority: .utility) {
          try await logSemaphor.waitUnlessCancelled()

          let mediaURLs = avQueuePlayer.items().map { MediaURL($0.assetURL) }
          let podcastEpisodes = IdentifiedArray(
            uniqueElements: try await Container.shared.repo().episodes(mediaURLs),
            id: \.episode.media
          )
          var podcastEpisodesFound: [PodcastEpisode] = []
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
              \(String(describing: self.loadedCurrentPodcastEpisode?.toString))
              MediaURL: \(String(describing:
                self.loadedCurrentPodcastEpisode?.podcastEpisode.episode.media))
            LoadedNextPodcastEpisode:
              \(String(describing: self.loadedNextPodcastEpisode?.toString))
              MediaURL: \(String(describing:
                self.loadedNextPodcastEpisode?.podcastEpisode.episode.media))
            """
          )

          log.debug(
            """
            insertNextPodcastEpisode: AVPlayer assets at end of function are:
              \(podcastEpisodesFound.map(\.toString).joined(separator: "\n  "))
            """
          )

          logSemaphor.signal()
        }
      }
    }

    log.debug(
      """
      insertNextPodcastEpisode: Inserting next episode: \
      \(String(describing: nextBundle?.loadedPodcastEpisode.toString))
      """
    )

    self.nextBundle = nextBundle

    if avQueuePlayer.items().isEmpty {
      log.debug("insertNextPodcastEpisode: avQueuePlayer queue is empty")
      return
    }

    if avQueuePlayer.items().count == 1 && loadedNextPodcastEpisode == nil {
      if log.wouldLog(.debug) {
        Task(priority: .utility) {
          try await logSemaphor.waitUnlessCancelled()

          guard let assetURL = avQueuePlayer.items().first?.assetURL,
            let podcastEpisode = try await Container.shared.repo().episode(MediaURL(assetURL))
          else { Assert.fatal("Could not find episode for first and only AVURLAsset") }

          log.debug(
            """
            insertNextPodcastEpisode: nothing to do because the incoming next episode is nil and \
            there's only one in the avQueuePlayer, which is \(podcastEpisode.toString), which must be \
            the one playing
            """
          )

          logSemaphor.signal()
        }
      }
      return
    }

    if avQueuePlayer.items().count == 2,
      avQueuePlayer.items().last?.assetURL == loadedNextPodcastEpisode?.assetURL
    {
      log.debug(
        """
        insertNextPodcastEpisode: nothing to do because the avQueuePlayer queue is the right \
        length of 2 and the incoming next episode is already in the #2 slot
        """
      )
      return
    }

    while avQueuePlayer.items().count > 1, let lastItem = avQueuePlayer.items().last {
      if log.wouldLog(.debug) {
        Task(priority: .utility) {
          try await logSemaphor.waitUnlessCancelled()

          guard
            let podcastEpisode = try await Container.shared.repo()
              .episode(MediaURL(lastItem.assetURL))
          else { Assert.fatal("Could not find episode for last AVURLAsset") }

          log.debug(
            """
            insertNextPodcastEpisode: Removing item from end of avQueuePlayer queue: \
            \(podcastEpisode.toString)
            """
          )

          logSemaphor.signal()
        }
      }
      avQueuePlayer.remove(lastItem)
    }

    if let nextBundle = self.nextBundle {
      log.debug(
        """
        insertNextPodcastEpisode: Adding \(nextBundle.loadedPodcastEpisode.toString) \
        to avQueuePlayer queue
        """
      )
      avQueuePlayer.insert(nextBundle.playableItem, after: avQueuePlayer.items().first)
    }
  }

  // MARK: - Private Change Handlers

  private func handleEpisodeFinished() throws(PlaybackError) {
    guard let finishedPodcastEpisode = self.podcastEpisode
    else { Assert.fatal("Finished episode but current episode is nil?") }

    log.debug("handleEpisodeFinished: Episode finished: \(finishedPodcastEpisode.toString)")

    loadedCurrentPodcastEpisode = loadedNextPodcastEpisode
    nextBundle = nil

    if let podcastEpisode = podcastEpisode {
      log.debug(
        """
        handleEpisodeFinished: new episode is \(podcastEpisode.toString) \
        Adding periodic time observer for next episode
        """
      )
      addPeriodicTimeObserver()
    } else {
      log.debug("handleEpisodeFinished: No next episode, removing periodic time observer")
      removePeriodicTimeObserver()
    }

    playToEndContinuation.yield((finishedPodcastEpisode, loadedCurrentPodcastEpisode))
  }

  // MARK: - Private Tracking

  private func addPeriodicTimeObserver() {
    guard self.periodicTimeObserver == nil
    else {
      log.notice("addPeriodicTimeObserver: Observer already exists, skipping")
      return
    }

    log.debug("addPeriodicTimeObserver: Adding periodic time observer")
    self.periodicTimeObserver = avQueuePlayer.addPeriodicTimeObserver(
      forInterval: CMTime.inSeconds(1),
      queue: .global(qos: .utility)
    ) { [weak self] currentTime in
      guard let self else { return }
      self.currentTimeContinuation.yield(currentTime)
    }
  }

  private func removePeriodicTimeObserver() {
    if let periodicTimeObserver = self.periodicTimeObserver {
      log.debug("removePeriodicTimeObserver: Removing periodic time observer")
      avQueuePlayer.removeTimeObserver(periodicTimeObserver)
      self.periodicTimeObserver = nil
    } else {
      log.notice("removePeriodicTimeObserver: No observer to remove")
    }
  }

  private func addTimeControlStatusObserver() {
    Assert.precondition(
      self.timeControlStatusObserver == nil,
      "timeControlStatusObserver already exists?"
    )

    self.timeControlStatusObserver = avQueuePlayer.observeTimeControlStatus(
      options: [.initial, .new]
    ) { status in
      self.controlStatusContinuation.yield(status)
    }
  }

  private func startPlayToEndTimeNotifications() {
    Assert.precondition(
      self.playToEndNotificationTask == nil,
      "playToEndNotificationTask already exists?"
    )

    self.playToEndNotificationTask = Task {
      for await _ in notifications(AVPlayerItem.didPlayToEndTimeNotification) {
        try? handleEpisodeFinished()
      }
    }
  }
}
