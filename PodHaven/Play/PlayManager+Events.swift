// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Logging

extension PlayManager {

  // MARK: - Change Handlers

  private func handleItemStatusChange(status: AVPlayerItem.Status, episodeID: Episode.ID) async {
    Self.log.debug("handleItemStatusChange: \(status) for episode \(episodeID)")

    if status == .failed {
      Self.log.warning("status is failed for \(episodeID), clearing on deck and unshifting")
      await stop()
      do {
        try await queue.unshift(episodeID)
      } catch {
        Self.log.caughtError(
          "handleItemStatusChange: failed to unshift episode \(episodeID) after status failure",
          error
        )
      }
    }
  }

  private func handleDidPlayToEnd(_ episodeID: Episode.ID) async {
    Self.log.debug("handleDidPlayToEnd: \(episodeID)")

    await finishEpisode(episodeID)
  }

  private func handleTrackBehaviorChange() {
    Self.log.debug(
      """
      handleTrackBehaviorChange:
        queueCount: \(sharedState.queueCount)
        onDeck: \(String(describing: sharedState.onDeck?.toString))
        nextTrackBehavior: \(userSettings.nextTrackBehavior)
      """
    )

    CommandCenter.updateNextTrack()
    NowPlayingInfo.updateQueueCount()
  }

  private func handleSkipIntervalsChange() {
    Self.log.debug(
      """
      handleSkipIntervalsChange:
        skipForwardInterval: \(userSettings.skipForwardInterval)
        skipBackwardInterval: \(userSettings.skipBackwardInterval)
      """
    )

    CommandCenter.updateSkipIntervals()
  }

  private func handleMediaServicesReset() async {
    Self.log.info("handleMediaServicesReset: beginning recovery process")

    guard configureAudioSession() else { return }
    Self.log.debug("handleMediaServicesReset: audio session configured")

    // Clean up the old AVPlayer before resetting, since @DynamicInjected re-resolves
    // on each access — after reset, avPlayer points to the new instance and the old
    // one's observers and player item would be leaked.
    await podAVPlayer.clear()

    Container.shared.avPlayer.reset(.scope)
    Self.log.debug("handleMediaServicesReset: reset AVPlayer scope")

    // Re-register on the fresh factory instances
    CommandCenter.registerRemoteCommandHandlers()
    Self.log.debug("handleMediaServicesReset: remote command handlers re-registered")

    let currentOnDeck = sharedState.onDeck
    await clearOnDeck()
    Self.log.debug("handleMediaServicesReset: cleared existing playback state")

    do {
      let episodeToLoad: PodcastEpisode?
      if let currentOnDeck {
        Self.log.debug("handleMediaServicesReset: recovering on-deck episode \(currentOnDeck.id)")
        episodeToLoad = try await repo.podcastEpisode(currentOnDeck.id)
      } else if let nextEpisode = try await queue.nextEpisode {
        Self.log.debug(
          """
          handleMediaServicesReset: no on-deck episode, \
          falling back to top of queue: \(nextEpisode.toString)
          """
        )
        episodeToLoad = nextEpisode
      } else {
        episodeToLoad = nil
      }

      guard let episodeToLoad else {
        Self.log.debug("handleMediaServicesReset: no episode to recover")
        return
      }

      Self.log.info("handleMediaServicesReset: reloading \(episodeToLoad.toString)")
      try await load(episodeToLoad)
      Self.log.info("handleMediaServicesReset: recovery finished successfully")
    } catch {
      Self.log.caughtError(
        "handleMediaServicesReset: failed to recover playback",
        error
      )
    }
  }

  // MARK: - Notification Tracking

  nonisolated func notificationTracking() {
    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await notification in notifications(AVAudioSession.interruptionNotification) {
        let parsedNotification = AudioInterruption.parse(notification)
        Self.log.debug("Got audio interruption notification: \(parsedNotification)")

        switch parsedNotification {
        case .pause:
          await pause()
        case .resume:
          await play()
        case .ignore:
          break
        }
      }
    }

    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await _ in notifications(AVAudioSession.mediaServicesWereLostNotification) {
        Self.log.error("Media services were lost")
      }
    }

    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await _ in notifications(AVAudioSession.mediaServicesWereResetNotification) {
        await handleMediaServicesReset()
      }
    }

    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await notification in notifications(AVAudioSession.routeChangeNotification) {
        guard
          let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
          let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        else { continue }

        let session = AVAudioSession.sharedInstance()
        Self.log.info(
          """
          Audio route changed
            reason: \(reason)
            outputs: \(session.currentRoute.outputs.map(\.portType.rawValue))
          """
        )

        await podAVPlayer.savePosition()
      }
    }

    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await notification in notifications(AVPlayerItem.failedToPlayToEndTimeNotification) {
        guard await podAVPlayer.isCurrentItem(notification.object as? AVPlayerItem) else {
          Self.log.warning("Ignoring failedToPlayToEndTimeNotification from non-current item")
          continue
        }

        guard
          let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey]
            as? any Error
        else { Assert.fatal("failedToPlayToEndTimeNotification: \(notification) is invalid") }

        Self.log.caughtError(
          "AVPlayerItem failed to play to end time",
          error,
          remarkable: .warning
        )

        await handlePlaybackFailure()
      }
    }

    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await notification in notifications(AVPlayerItem.timeJumpedNotification)
      where await podAVPlayer.isCurrentItem(notification.object as? AVPlayerItem) {
        let time = (notification.object as? AVPlayerItem)?.currentTime()
        Self.log.info("AVPlayerItem time jumped to \(String(describing: time))")
      }
    }

    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await notification in notifications(AVPlayerItem.playbackStalledNotification) {
        guard await podAVPlayer.isCurrentItem(notification.object as? AVPlayerItem) else {
          Self.log.warning("Ignoring playbackStalledNotification from non-current item")
          continue
        }
        Self.log.warning("AVPlayerItem playback stalled")
      }
    }

    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await notification in notifications(AVPlayerItem.newErrorLogEntryNotification) {
        guard let item = notification.object as? AVPlayerItem
        else { Assert.fatal("newErrorLogEntryNotification: \(notification) is invalid") }

        guard await podAVPlayer.isCurrentItem(item) else {
          Self.log.warning("Ignoring newErrorLogEntryNotification from non-current item")
          continue
        }

        guard let errorLog = item.errorLog()
        else { Assert.fatal("newErrorLogEntryNotification fired but errorLog() returned nil?") }

        Self.log.warning(
          """
          Error log events for episode \
            \(String(describing: sharedState.onDeck?.id)) (\(errorLog.events.count)):
            \(errorLog.events.map { event in
              String(describing: event.errorComment)
            }.joined(separator: "\n  "))
          """
        )
      }
    }
  }

  // MARK: - Subordinate Async Streams

  nonisolated func asyncStreams() {
    // CommandCenter

    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await command in commandCenterStream.stream {
        switch command {
        case .play:
          await play()
        case .pause:
          await pause()
        case .togglePlayPause:
          await toggle()
        case .skipForward(let interval):
          await seekForward(interval)
        case .skipBackward(let interval):
          await seekBackward(interval)
        case .playbackPosition(let position, let sourceEpisodeID):
          guard let sourceEpisodeID, let currentEpisodeID = sharedState.onDeck?.id else {
            Self.log.debug(
              """
              playManager: dropping remote scrub to \(position) because no on-deck episode is \
              bound
              """
            )
            continue
          }

          guard sourceEpisodeID == currentEpisodeID else {
            Self.log.debug(
              """
              playManager: dropping stale remote scrub to \(position) from episode \
              \(sourceEpisodeID) while current episode is \(currentEpisodeID)
              """
            )
            continue
          }

          if ignoreRemoteScrubCommands {
            Self.log.debug("playManager: ignoring remote scrub to \(position) during transition")
            continue
          }
          await seek(to: CMTime.seconds(position))
        case .changePlaybackRate(let rate):
          await setRate(rate)
        case .nextEpisode:
          switch userSettings.nextTrackBehavior {
          case .nextEpisode:
            await finishEpisode()
          case .skipInterval:
            await seekForward()
          case .nextChapter:
            await seekToNextChapter()
          }
        case .previousEpisode:
          switch userSettings.nextTrackBehavior {
          case .nextEpisode:
            await seek(to: .zero)
          case .skipInterval:
            await seekBackward()
          case .nextChapter:
            await seekToPreviousChapter()
          }
        }
      }
    }

    // PodAVPlayer

    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await (status, episodeID) in await podAVPlayer.itemStatusStream {
        await handleItemStatusChange(status: status, episodeID: episodeID)
      }
    }

    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await currentTime in await podAVPlayer.currentTimeStream {
        await setCurrentTime(currentTime)
      }
    }

    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await rate in await podAVPlayer.rateStream {
        await setPlaybackRate(rate)
      }
    }

    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await controlStatus in await podAVPlayer.controlStatusStream {
        Self.log.debug("AVPlayer timeControlStatus changed to: \(controlStatus)")
        switch controlStatus {
        case .paused:
          await setStatus(.paused)
        case .playing:
          await setStatus(.playing)
        case .waiting:
          await setStatus(.waiting)
        case .loading(_), .stopped:
          Assert.fatal("\(controlStatus) from PodAVPlayer?")
        }
      }
    }

    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await episodeID in await podAVPlayer.didPlayToEndStream {
        await handleDidPlayToEnd(episodeID)
      }
    }

    // UserSettings

    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await _ in userSettings.$nextTrackBehavior.stream() {
        Self.log.debug("nextTrackBehavior changed")
        handleTrackBehaviorChange()
      }
    }

    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await _ in userSettings.$skipForwardInterval.stream() {
        Self.log.debug("skipForwardInterval changed")
        handleSkipIntervalsChange()
      }
    }

    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await _ in userSettings.$skipBackwardInterval.stream() {
        Self.log.debug("skipBackwardInterval changed")
        handleSkipIntervalsChange()
      }
    }

    // SharedState

    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await _ in sharedState.$queuedPodcastEpisodes.stream() {
        Self.log.debug("queue changed")
        handleTrackBehaviorChange()
      }
    }
  }
}
