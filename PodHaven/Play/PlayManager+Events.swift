// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Logging
import MediaPlayer

extension PlayManager {

  @MainActor private static func resetAVPlayerScope() {
    Container.shared.avPlayer.reset(.scope)
  }

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

  // Snapshot both our view of playback state (AVPlayer currentTime,
  // timeControlStatus, reasonForWaitingToPlay) and iOS's dict view (elapsed,
  // rate). `label` identifies the caller (periodic, pause, post-pause +5s,
  // etc.) so the next stale-scrub incident has a trail of checkpoints across
  // the whole session leading up to, through, and past the pause window.
  func logBackgroundPlaybackSnapshot(label: String, currentTime: CMTime) async {
    let avPlayerPlaybackStatus = await podAVPlayer.playbackStatus()
    let waitingReason = await podAVPlayer.reasonForWaitingToPlay()
    let applicationState = await Container.shared.uiApplication().applicationState
    let routeOutputs = AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portType.rawValue)
    let infoCenter = Container.shared.mpNowPlayingInfoCenter()
    let nowPlayingElapsed: Double? =
      infoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double
    let nowPlayingRate: Double? =
      infoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? Double

    let elapsedString: String
    if let nowPlayingElapsed {
      elapsedString = String(describing: CMTime.seconds(nowPlayingElapsed))
    } else {
      elapsedString = "nil"
    }

    Self.log.debug(
      """
      playback snapshot (\(label))
        avPlayerCurrentTime: \(currentTime)
        nowPlayingElapsed: \(elapsedString)
        nowPlayingRate: \(String(describing: nowPlayingRate))
        sharedPlaybackStatus: \(sharedState.playbackStatus)
        avPlayerPlaybackStatus: \(avPlayerPlaybackStatus)
        waitingReason: \(String(describing: waitingReason))
        appState: \(applicationState)
        routeOutputs: \(routeOutputs)
      """
    )
  }

  private func logRemoteScrubDecision(
    action: String,
    requestedPosition: TimeInterval,
    sourceEpisodeID: Episode.ID?,
    currentEpisodeID: Episode.ID?,
    eventTimestamp: TimeInterval,
    reason: String? = nil
  ) async {
    let onDeck = sharedState.onDeck
    let avPlayerCurrentTime = await podAVPlayer.currentTime()
    let avPlayerPlaybackStatus = await podAVPlayer.playbackStatus()
    let applicationState = await Container.shared.uiApplication().applicationState
    let routeOutputs = AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portType.rawValue)
    let infoCenter = Container.shared.mpNowPlayingInfoCenter()
    let nowPlayingElapsed =
      infoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double
    let nowPlayingElapsedString: String
    if let nowPlayingElapsed {
      nowPlayingElapsedString = String(describing: CMTime.seconds(nowPlayingElapsed))
    } else {
      nowPlayingElapsedString = "nil"
    }
    // User-initiated lock-screen scrubs carry an event timestamp stamped at
    // tap time, so the lag against Date() is ~0. System-generated scrubs that
    // arrive mid-AirPods-reconnect appear to be stamped at the internal
    // capture moment (pre-pause), producing a multi-second lag that the user
    // cannot physically replicate. MPRemoteCommandEvent.timestamp base is
    // NSDate.timeIntervalSinceReferenceDate.
    let eventLag = Date().timeIntervalSinceReferenceDate - eventTimestamp

    Self.log.debug(
      """
      \(action) remote scrub
        requestedPosition: \(CMTime.seconds(requestedPosition))
        sourceEpisodeID: \(String(describing: sourceEpisodeID))
        currentEpisodeID: \(String(describing: currentEpisodeID))
        onDeckTitle: \(String(describing: onDeck?.title))
        sharedCurrentTime: \(String(describing: onDeck?.currentTime))
        avPlayerCurrentTime: \(avPlayerCurrentTime)
        nowPlayingElapsed: \(nowPlayingElapsedString)
        sharedPlaybackStatus: \(sharedState.playbackStatus)
        avPlayerPlaybackStatus: \(avPlayerPlaybackStatus)
        ignoreRemoteScrubCommands: \(ignoreRemoteScrubCommands)
        appState: \(applicationState)
        routeOutputs: \(routeOutputs)
        eventTimestamp: \(eventTimestamp)
        eventLagSeconds: \(eventLag)
        reason: \(reason ?? "accepted")
      """
    )
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

  private func handleScrubbingChange() {
    Self.log.debug(
      "handleScrubbingChange: commandCenterScrubbingEnabled: \(userSettings.commandCenterScrubbingEnabled)"
    )

    CommandCenter.updateScrubbing()
  }

  private func handleMediaServicesReset() async {
    Self.log.info("handleMediaServicesReset: beginning recovery process")

    guard await Container.shared.configureAudioSession()() else {
      await stop()
      return
    }
    Self.log.debug("handleMediaServicesReset: audio session configured")

    // Clean up the old AVPlayer before resetting, since @DynamicInjected re-resolves
    // on each access — after reset, avPlayer points to the new instance and the old
    // one's observers and player item would be leaked.
    await podAVPlayer.clear()

    await Self.resetAVPlayerScope()
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
        let userInfo = notification.userInfo ?? [:]
        let typeRaw = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt
        let optionsRaw = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt
        let reasonRaw = userInfo[AVAudioSessionInterruptionReasonKey] as? UInt
        let reasonDescription: String
        if let reasonRaw, let reason = AVAudioSession.InterruptionReason(rawValue: reasonRaw) {
          reasonDescription = String(describing: reason)
        } else {
          reasonDescription = "nil"
        }
        Self.log.info(
          """
          Audio interruption notification
            parsed: \(parsedNotification)
            typeRaw: \(String(describing: typeRaw))
            optionsRaw: \(String(describing: optionsRaw))
            reason: \(reasonDescription)
          """
        )

        switch parsedNotification {
        case .pause:
          await pause()
          let pausedAt = await podAVPlayer.currentTime()
          await logBackgroundPlaybackSnapshot(label: "pause", currentTime: pausedAt)
          startPostPauseObservation()
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
        Self.log.notice("Media services were lost")
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
        let previousRoute =
          notification.userInfo?[AVAudioSessionRouteChangePreviousRouteKey]
          as? AVAudioSessionRouteDescription
        let previousOutputs = previousRoute?.outputs.map(\.portType.rawValue) ?? []
        Self.log.info(
          """
          Audio route changed
            reason: \(reason)
            previousOutputs: \(previousOutputs)
            outputs: \(session.currentRoute.outputs.map(\.portType.rawValue))
          """
        )

        guard sharedState.onDeck != nil else { continue }
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
          level: .warning
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
        case .playbackPosition(let position, let sourceEpisodeID, let eventTimestamp):
          guard let sourceEpisodeID, let currentEpisodeID = sharedState.onDeck?.id else {
            await logRemoteScrubDecision(
              action: "dropping",
              requestedPosition: position,
              sourceEpisodeID: sourceEpisodeID,
              currentEpisodeID: sharedState.onDeck?.id,
              eventTimestamp: eventTimestamp,
              reason: "no on-deck episode bound"
            )
            continue
          }

          guard sourceEpisodeID == currentEpisodeID else {
            await logRemoteScrubDecision(
              action: "dropping",
              requestedPosition: position,
              sourceEpisodeID: sourceEpisodeID,
              currentEpisodeID: currentEpisodeID,
              eventTimestamp: eventTimestamp,
              reason: "stale command for non-current episode"
            )
            continue
          }

          if ignoreRemoteScrubCommands {
            await logRemoteScrubDecision(
              action: "ignoring",
              requestedPosition: position,
              sourceEpisodeID: sourceEpisodeID,
              currentEpisodeID: currentEpisodeID,
              eventTimestamp: eventTimestamp,
              reason: "transition in progress"
            )
            continue
          }

          await logRemoteScrubDecision(
            action: "applying",
            requestedPosition: position,
            sourceEpisodeID: sourceEpisodeID,
            currentEpisodeID: currentEpisodeID,
            eventTimestamp: eventTimestamp
          )
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
        case .bookmark(let sourceEpisodeID):
          guard let sourceEpisodeID else {
            Self.log.debug("bookmark command received with no on-deck episode, ignoring")
            continue
          }
          await toggleSaveInCache(sourceEpisodeID)
        case .like(let sourceEpisodeID):
          guard let sourceEpisodeID else {
            Self.log.debug("like command received with no on-deck episode, ignoring")
            continue
          }
          switch userSettings.commandCenterLikeAction {
          case .love: await toggleRating(.loved, for: sourceEpisodeID)
          case .like: await toggleRating(.liked, for: sourceEpisodeID)
          case .saveInCache: await toggleSaveInCache(sourceEpisodeID)
          case .addTag(let tagID): await toggleTag(tagID, for: sourceEpisodeID)
          }
        case .dislike(let sourceEpisodeID):
          guard let sourceEpisodeID else {
            Self.log.debug("dislike command received with no on-deck episode, ignoring")
            continue
          }
          switch userSettings.commandCenterDislikeAction {
          case .dislike: await toggleRating(.disliked, for: sourceEpisodeID)
          case .addTag(let tagID): await toggleTag(tagID, for: sourceEpisodeID)
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
        setCurrentTime(currentTime)
      }
    }

    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await rate in await podAVPlayer.rateStream {
        setPlaybackRate(rate)
      }
    }

    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await controlStatus in await podAVPlayer.controlStatusStream {
        Self.log.debug("AVPlayer timeControlStatus changed to: \(controlStatus)")
        switch controlStatus {
        case .paused:
          setStatus(.paused)
        case .playing:
          setStatus(.playing)
        case .waiting:
          setStatus(.waiting)
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
        Self.log.debug("nextTrackBehavior changed to: \(userSettings.nextTrackBehavior)")
        handleTrackBehaviorChange()
      }
    }

    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await _ in userSettings.$skipForwardInterval.stream() {
        Self.log.debug("skipForwardInterval changed to: \(userSettings.skipForwardInterval)s")
        handleSkipIntervalsChange()
      }
    }

    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await _ in userSettings.$skipBackwardInterval.stream() {
        Self.log.debug("skipBackwardInterval changed to: \(userSettings.skipBackwardInterval)s")
        handleSkipIntervalsChange()
      }
    }

    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await _ in userSettings.$commandCenterScrubbingEnabled.stream() {
        Self.log.debug(
          "commandCenterScrubbingEnabled changed to: \(userSettings.commandCenterScrubbingEnabled)"
        )
        handleScrubbingChange()
      }
    }

    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await _ in userSettings.$alwaysShowPodcastImageForOnDeck.stream() {
        refetchOnDeckImage()
      }
    }

    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await _ in userSettings.$commandCenterLikeAction.stream() {
        CommandCenter.updateFeedbackCommands()
      }
    }

    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await _ in userSettings.$commandCenterDislikeAction.stream() {
        CommandCenter.updateFeedbackCommands()
      }
    }

    // SharedState

    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await _ in sharedState.$queuedPodcastEpisodes.stream() {
        Self.log.debug("queue changed, count: \(sharedState.queueCount)")
        handleTrackBehaviorChange()
      }
    }

    // onDeck re-emits whenever the current episode's row changes (rating,
    // saveInCache, tags from any source), keeping the bookmark and like/dislike
    // active states in sync.
    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await _ in sharedState.$onDeck.stream() {
        CommandCenter.updateBookmark()
        CommandCenter.updateFeedbackCommands()
      }
    }

    // Tag renames/adds/deletes change the "Add Tag" feedback button titles and
    // can orphan a configured tag, so keep the like/dislike titles in sync.
    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await _ in sharedState.$tags.stream() {
        CommandCenter.updateFeedbackCommands()
      }
    }
  }
}
