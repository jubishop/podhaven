// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation

extension Container {
  @PlayActor
  var podAVPlayer: Factory<PodAVPlayer> {
    Factory(self) { @PlayActor in PodAVPlayer() }.scope(.cached)
  }
}

@PlayActor final class PodAVPlayer: Sendable {
  // MARK: - Convenience Getters

  var podcastEpisode: PodcastEpisode? { loadedCurrentPodcastEpisode?.podcastEpisode }
  var nextPodcastEpisode: PodcastEpisode? { loadedNextPodcastEpisode?.podcastEpisode }

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
    removePeriodicTimeObserver()
    avPlayer.removeAllItems()
    self.loadedCurrentPodcastEpisode = nil
  }

  func load(_ podcastEpisode: PodcastEpisode) async throws(PlaybackError) -> CMTime {
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
    avPlayer.play()
  }

  func pause() {
    avPlayer.pause()
  }

  // MARK: - Seeking

  func seekForward(_ duration: CMTime) async {
    await seek(to: avPlayer.currentTime() + duration)
  }

  func seekBackward(_ duration: CMTime) async {
    await seek(to: avPlayer.currentTime() - duration)
  }

  func seek(to time: CMTime) async {
    removePeriodicTimeObserver()
    currentTimeContinuation.yield(time)
    avPlayer.seek(to: time) { completed in
      if completed {
        Task { await self.addPeriodicTimeObserver() }
      }
    }
  }

  // MARK: - State Setters

  func setNextPodcastEpisode(_ nextPodcastEpisode: PodcastEpisode?) async {
    guard nextPodcastEpisode?.id != self.nextPodcastEpisode?.id
    else { return }

    if let podcastEpisode = nextPodcastEpisode {
      do {
        insertNextPodcastEpisode(try await loadAsset(for: podcastEpisode))
      } catch {
        insertNextPodcastEpisode(nil)
      }
    } else {
      insertNextPodcastEpisode(nil)
    }
  }

  // MARK: - Private State Management

  private func insertNextPodcastEpisode(_ loadedNextPodcastEpisode: LoadedPodcastEpisode?) {
    self.loadedNextPodcastEpisode = loadedNextPodcastEpisode

    if (avPlayer.items().isEmpty)
      || (avPlayer.items().count == 1 && loadedNextPodcastEpisode == nil)
      || (avPlayer.items().count == 2 && avPlayer.items().last == loadedNextPodcastEpisode?.item)
    {
      return
    }

    while avPlayer.items().count > 1, let lastItem = avPlayer.items().last {
      avPlayer.remove(lastItem)
    }

    if let loadedNextPodcastEpisode = self.loadedNextPodcastEpisode {
      avPlayer.insert(loadedNextPodcastEpisode.item, after: avPlayer.items().first)
    }
  }

  // MARK: - Private Change Handlers

  private func handleEpisodeFinished() async throws(PlaybackError) {
    guard let finishedPodcastEpisode = self.podcastEpisode
    else { throw PlaybackError.finishedEpisodeIsNil }

    loadedCurrentPodcastEpisode = loadedNextPodcastEpisode
    loadedNextPodcastEpisode = nil

    if podcastEpisode != nil {
      addPeriodicTimeObserver()
    } else {
      removePeriodicTimeObserver()
    }

    playToEndContinuation.yield((finishedPodcastEpisode, loadedCurrentPodcastEpisode))
  }

  // MARK: - Private Tracking

  private func addPeriodicTimeObserver() {
    guard self.periodicTimeObserver == nil
    else { return }

    self.periodicTimeObserver = avPlayer.addPeriodicTimeObserver(
      forInterval: CMTime.inSeconds(1),
      queue: .global(qos: .utility)
    ) { currentTime in
      self.currentTimeContinuation.yield(currentTime)
    }
  }

  private func removePeriodicTimeObserver() {
    if let periodicTimeObserver = self.periodicTimeObserver {
      avPlayer.removeTimeObserver(periodicTimeObserver)
      self.periodicTimeObserver = nil
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
