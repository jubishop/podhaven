// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import IdentifiedCollections
import Logging
import Semaphore

extension Container {
  @PlayActor
  var podAVPlayer: Factory<PodAVPlayer> {
    Factory(self) { @PlayActor in PodAVPlayer() }.scope(.cached)
  }
}

@PlayActor final class PodAVPlayer: Sendable {
  private let log = Log.as(LogSubsystem.Play.avPlayer)

  // MARK: - Convenience Getters

  var podcastEpisode: PodcastEpisode? { loadedCurrentPodcastEpisode?.podcastEpisode }
  var nextPodcastEpisode: PodcastEpisode? { loadedNextPodcastEpisode?.podcastEpisode }

  // MARK: - Debugging

  private let mainActorLogSemaphore = AsyncSemaphore(value: 1)

  // MARK: - State Management

  private var loadedNextPodcastEpisode: LoadedPodcastEpisode?
  private var loadedCurrentPodcastEpisode: LoadedPodcastEpisode?

  let currentTimeStream: AsyncStream<CMTime>
  let controlStatusStream: AsyncStream<AVPlayer.TimeControlStatus>
  let playToEndStream: AsyncStream<(PodcastEpisode, LoadedPodcastEpisode?)>
  private let currentTimeContinuation: AsyncStream<CMTime>.Continuation
  private let controlStatusContinuation: AsyncStream<AVPlayer.TimeControlStatus>.Continuation
  private let playToEndContinuation:
    AsyncStream<(PodcastEpisode, LoadedPodcastEpisode?)>.Continuation

  private var timeControlStatusObserver: NSKeyValueObservation?
  private var periodicTimeObserver: Any?
  private var playToEndNotificationTask: Task<Void, Never>?

  private var avPlayer = AVQueuePlayer()

  // MARK: - Initialization

  fileprivate init() {
    (self.currentTimeStream, self.currentTimeContinuation) = AsyncStream.makeStream(
      of: CMTime.self
    )
    (self.controlStatusStream, self.controlStatusContinuation) = AsyncStream.makeStream(
      of: AVPlayer.TimeControlStatus.self
    )
    (self.playToEndStream, self.playToEndContinuation) = AsyncStream.makeStream(
      of: (PodcastEpisode, LoadedPodcastEpisode?).self
    )

    addPeriodicTimeObserver()
    addTimeControlStatusObserver()
    startPlayToEndTimeNotifications()
  }

  // MARK: - Loading

  func stop() {
    log.debug("stop: executing")
    removePeriodicTimeObserver()
    avPlayer.removeAllItems()
    self.loadedCurrentPodcastEpisode = nil
  }

  func load(_ podcastEpisode: PodcastEpisode) async throws(PlaybackError) -> CMTime {
    log.debug("avPlayer loading: \(podcastEpisode.toString)")

    let loadedPodcastEpisode = try await loadAsset(for: podcastEpisode)
    self.loadedCurrentPodcastEpisode = loadedPodcastEpisode

    avPlayer.removeAllItems()
    avPlayer.insert(loadedPodcastEpisode.item, after: nil)
    insertNextPodcastEpisode(self.loadedNextPodcastEpisode)
    addPeriodicTimeObserver()

    return loadedPodcastEpisode.duration
  }

  private func loadAsset(for podcastEpisode: PodcastEpisode) async throws(PlaybackError)
    -> LoadedPodcastEpisode
  {
    let avAsset = AVURLAsset(url: podcastEpisode.episode.media.rawValue)
    let (isPlayable, duration): (Bool, CMTime)
    do {
      (isPlayable, duration) = try await avAsset.load(.isPlayable, .duration)
    } catch {
      throw PlaybackError.loadFailure(podcastEpisode: podcastEpisode, caught: error)
    }

    guard isPlayable
    else { throw PlaybackError.mediaNotPlayable(podcastEpisode) }

    return LoadedPodcastEpisode(
      item: AVPlayerItem(asset: avAsset),
      podcastEpisode: podcastEpisode,
      duration: duration
    )
  }

  // MARK: - Playback Controls

  func play() {
    log.debug("play: executing, playing \(String(describing: podcastEpisode?.toString))")
    avPlayer.play()
  }

  func pause() {
    log.debug("pause: executing, pausing \(String(describing: podcastEpisode?.toString))")
    avPlayer.pause()
  }

  // MARK: - Seeking

  func seekForward(_ duration: CMTime) async {
    log.debug(
      """
      seekForward: seeking forward by \(duration) for \
      \(String(describing: podcastEpisode?.toString))
      """
    )
    await seek(to: avPlayer.currentTime() + duration)
  }

  func seekBackward(_ duration: CMTime) async {
    log.debug(
      """
      seekForward: seeking backward by \(duration) for \
      \(String(describing: podcastEpisode?.toString))
      """
    )
    await seek(to: avPlayer.currentTime() - duration)
  }

  func seek(to time: CMTime) async {
    log.debug(
      """
      seek: seeking to time \(time) for \
      \(String(describing: podcastEpisode?.toString))
      """
    )
    removePeriodicTimeObserver()
    currentTimeContinuation.yield(time)
    avPlayer.seek(to: time) { [weak self] completed in
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
      log.warning(
        """
        setNextPodcastEpisode: Trying to set next episode to \
        \(String(describing: nextPodcastEpisode?.toString)) \
        but it is the same as the current episode
        """
      )
      return
    }

    if let podcastEpisode = nextPodcastEpisode {
      do {
        insertNextPodcastEpisode(try await loadAsset(for: podcastEpisode))
      } catch {
        log.error(error)
        insertNextPodcastEpisode(nil)
      }
    } else {
      insertNextPodcastEpisode(nil)
    }
  }

  // MARK: - Private State Management

  private func insertNextPodcastEpisode(_ loadedNextPodcastEpisode: LoadedPodcastEpisode?) {
    defer {
      if log.wouldLog(.debug) {
        Task(priority: .utility) { @MainActor in
          await mainActorLogSemaphore.wait()

          let mediaURLs = await avPlayer.items()
            .map {
              guard let urlAsset = $0.asset as? AVURLAsset
              else { Assert.fatal("\($0.asset) is not an AVURLAsset") }
              return MediaURL(urlAsset.url)
            }
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
              \(String(describing: await self.loadedCurrentPodcastEpisode?.toString))
              MediaURL: \(String(describing:
                await self.loadedCurrentPodcastEpisode?.podcastEpisode.episode.media))
            LoadedNextPodcastEpisode:
              \(String(describing: await self.loadedNextPodcastEpisode?.toString))
              MediaURL: \(String(describing:
                await self.loadedNextPodcastEpisode?.podcastEpisode.episode.media))
            """
          )

          log.debug(
            """
            insertNextPodcastEpisode: AVPlayer assets at end of function are:
              \(podcastEpisodesFound.map(\.toString).joined(separator: "\n  "))
            """
          )

          mainActorLogSemaphore.signal()
        }
      }
    }

    log.debug(
      """
      insertNextPodcastEpisode: Inserting next episode: \
      \(String(describing: loadedNextPodcastEpisode?.podcastEpisode.toString))
      """
    )

    self.loadedNextPodcastEpisode = loadedNextPodcastEpisode

    if avPlayer.items().isEmpty {
      log.debug("insertNextPodcastEpisode: avPlayer queue is empty")
      return
    }

    if avPlayer.items().count == 1 && loadedNextPodcastEpisode == nil {
      if log.wouldLog(.debug) {
        Task(priority: .utility) { @MainActor in
          await mainActorLogSemaphore.wait()

          guard let urlAsset = await avPlayer.items().first?.asset as? AVURLAsset,
            let podcastEpisode = try await Container.shared.repo().episode(MediaURL(urlAsset.url))
          else { Assert.fatal("Could not find episode for first and only AVURLAsset") }

          log.debug(
            """
            insertNextPodcastEpisode: nothing to do because the incoming next episode is nil and \
            there's only one in the avPlayer, which is \(podcastEpisode.toString), which must be \
            the one playing
            """
          )

          mainActorLogSemaphore.signal()
        }
      }
      return
    }

    if avPlayer.items().count == 2 && avPlayer.items().last == loadedNextPodcastEpisode?.item {
      log.debug(
        """
        insertNextPodcastEpisode: nothing to do because the avPlayer queue already is the right \
        length of 2 and the incoming next episode is already in the #2 slot
        """
      )
      return
    }

    while avPlayer.items().count > 1, let lastItem = avPlayer.items().last {
      if log.wouldLog(.debug) {
        Task(priority: .utility) { @MainActor in
          await mainActorLogSemaphore.wait()

          guard let urlAsset = lastItem.asset as? AVURLAsset,
            let podcastEpisode = try await Container.shared.repo().episode(MediaURL(urlAsset.url))
          else { Assert.fatal("Could not find episode for last AVURLAsset") }

          log.debug(
            """
            insertNextPodcastEpisode: Removing item from end of avPlayer queue: \
            \(podcastEpisode.toString)
            """
          )

          mainActorLogSemaphore.signal()
        }
      }
      avPlayer.remove(lastItem)
    }

    if let loadedNextPodcastEpisode = self.loadedNextPodcastEpisode {
      log.debug(
        """
        insertNextPodcastEpisode: Adding \(loadedNextPodcastEpisode.podcastEpisode.toString) \
        to avPlayer queue
        """
      )
      avPlayer.insert(loadedNextPodcastEpisode.item, after: avPlayer.items().first)
    }
  }

  // MARK: - Private Change Handlers

  private func handleEpisodeFinished() async throws(PlaybackError) {
    guard let finishedPodcastEpisode = self.podcastEpisode
    else { Assert.fatal("Finished episode but current episode is nil?") }

    log.debug("handleEpisodeFinished: Episode finished: \(finishedPodcastEpisode.toString)")

    loadedCurrentPodcastEpisode = loadedNextPodcastEpisode
    loadedNextPodcastEpisode = nil

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
    self.periodicTimeObserver = avPlayer.addPeriodicTimeObserver(
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
      avPlayer.removeTimeObserver(periodicTimeObserver)
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

    self.timeControlStatusObserver = avPlayer.observe(
      \.timeControlStatus,
      options: [.initial, .new],
      changeHandler: { playerItem, _ in
        self.controlStatusContinuation.yield(playerItem.timeControlStatus)
      }
    )
  }

  private func startPlayToEndTimeNotifications() {
    Assert.precondition(
      self.playToEndNotificationTask == nil,
      "playToEndNotificationTask already exists?"
    )

    self.playToEndNotificationTask = Task {
      for await _ in NotificationCenter.default.notifications(
        named: AVPlayerItem.didPlayToEndTimeNotification
      ) {
        try? await handleEpisodeFinished()
      }
    }
  }
}
