// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Foundation
import Logging

extension PlayManager {
  enum PlaybackRequestOrigin: String {
    case application
    case widget
  }

  struct AudioRouteChange {
    let currentOutputs: [String]
    let id: UUID
    let occurredAt: Date
    let previousOutputs: [String]
    let reason: AVAudioSession.RouteChangeReason
  }

  struct WidgetRouteRecovery {
    enum Phase {
      case requested
      case retrying(waitingAt: CMTime, routeChangeID: UUID)
      case retryScheduled(waitingAt: CMTime, routeChangeID: UUID)
      case routeChanged(UUID)
      case timingOut(waitingAt: CMTime, routeChangeID: UUID)
      case waiting(at: CMTime, routeChangeID: UUID?)
    }

    let episodeID: Episode.ID
    let isFromCache: Bool
    var phase: Phase
    let playerSource: PodAVPlayerEventSource
    let requestID: UUID
    let requestedAt: Date
    let requestedTime: CMTime
  }

  func beginPlaybackRequest(
    origin: PlaybackRequestOrigin,
    requestID: UUID,
    episodeID: Episode.ID,
    snapshot: PodAVPlayerPlaybackSnapshot
  ) async {
    let applicationState = await Container.shared.uiApplication().applicationState
    let routeOutputs = AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portType.rawValue)
    Self.log.info(
      """
      event=playRequest requestID=\(requestID) origin=\(origin.rawValue) episodeID=\(episodeID) \
      playerGeneration=\(String(describing: snapshot.source?.generation)) \
      appState=\(applicationState) currentTime=\(snapshot.currentTime) \
      itemStatus=\(String(describing: snapshot.itemStatus)) cached=\(snapshot.isFromCache) \
      timeControlStatus=\(snapshot.status) \
      waitingReason=\(String(describing: snapshot.waitingReason)) routeOutputs=\(routeOutputs)
      """
    )

    guard origin == .widget, let playerSource = snapshot.source else { return }
    let routeChangeID: UUID?
    if let latestAudioRouteChange {
      let elapsed = dateProvider.now.timeIntervalSince(latestAudioRouteChange.occurredAt)
      routeChangeID =
        elapsed >= 0 && elapsed <= routeChangeAssociationWindow ? latestAudioRouteChange.id : nil
    } else {
      routeChangeID = nil
    }
    let phase: WidgetRouteRecovery.Phase =
      if let routeChangeID {
        .routeChanged(routeChangeID)
      } else {
        .requested
      }
    widgetRouteRecovery = WidgetRouteRecovery(
      episodeID: episodeID,
      isFromCache: snapshot.isFromCache,
      phase: phase,
      playerSource: playerSource,
      requestID: requestID,
      requestedAt: dateProvider.now,
      requestedTime: snapshot.currentTime
    )
  }

  func recordAudioRouteChange(
    reason: AVAudioSession.RouteChangeReason,
    previousOutputs: [String],
    currentOutputs: [String]
  ) {
    let routeChange = AudioRouteChange(
      currentOutputs: currentOutputs,
      id: UUID(),
      occurredAt: dateProvider.now,
      previousOutputs: previousOutputs,
      reason: reason
    )
    latestAudioRouteChange = routeChange
    guard var recovery = widgetRouteRecovery else { return }

    let elapsed = dateProvider.now.timeIntervalSince(recovery.requestedAt)
    switch recovery.phase {
    case .requested where elapsed >= 0 && elapsed <= routeChangeAssociationWindow:
      recovery.phase = .routeChanged(routeChange.id)
    case .routeChanged:
      recovery.phase = .routeChanged(routeChange.id)
    case .waiting(let waitingAt, _):
      guard elapsed >= 0 && elapsed <= routeChangeAssociationWindow else { return }
      recovery.phase = .waiting(at: waitingAt, routeChangeID: routeChange.id)
    case .retryScheduled(let waitingAt, _):
      guard elapsed >= 0 && elapsed <= routeChangeAssociationWindow else { return }
      recovery.phase = .retryScheduled(waitingAt: waitingAt, routeChangeID: routeChange.id)
      widgetRouteRecovery = recovery
      scheduleWidgetRouteRecovery(recovery)
      return
    case .requested, .retrying, .timingOut:
      return
    }
    widgetRouteRecovery = recovery
    Self.log.debug(
      """
      event=widgetRouteRecoveryRouteAssociated requestID=\(recovery.requestID) \
      episodeID=\(recovery.episodeID) playerGeneration=\(recovery.playerSource.generation) \
      routeChangeID=\(routeChange.id) reason=\(reason) previousOutputs=\(previousOutputs) \
      currentOutputs=\(currentOutputs)
      """
    )
  }

  func handleWidgetRouteRecoveryStatus(_ event: PodAVPlayerEvent<PlaybackStatus>) async {
    guard var recovery = widgetRouteRecovery else { return }
    guard recovery.playerSource == event.source else {
      cancelWidgetRouteRecovery(reason: "playerGenerationChanged")
      return
    }
    let snapshot = await podAVPlayer.playbackSnapshot()
    guard snapshot.source == recovery.playerSource,
      sharedState.onDeck?.id == recovery.episodeID
    else {
      cancelWidgetRouteRecovery(reason: "playbackOwnershipChanged")
      return
    }

    switch event.value {
    case .waiting:
      switch recovery.phase {
      case .requested, .routeChanged, .waiting:
        guard snapshot.waitingReason == AVPlayer.WaitingReason.evaluatingBufferingRate.rawValue
        else { return }
        let routeChangeID: UUID?
        if case .routeChanged(let id) = recovery.phase {
          routeChangeID = id
        } else if case .waiting(_, let id) = recovery.phase {
          routeChangeID = id
        } else {
          routeChangeID = nil
        }
        recovery.phase = .waiting(at: snapshot.currentTime, routeChangeID: routeChangeID)
        widgetRouteRecovery = recovery
      case .retryScheduled, .retrying, .timingOut:
        break
      }
    case .paused:
      switch recovery.phase {
      case .waiting(let waitingAt, let routeChangeID):
        guard let routeChangeID else {
          skipWidgetRouteRecovery(recovery, reason: "noRouteChange")
          return
        }
        guard recovery.isFromCache else {
          skipWidgetRouteRecovery(recovery, reason: "notCached")
          return
        }
        guard !routeRecoveryHasProgressed(snapshot.currentTime, since: recovery.requestedTime)
        else {
          skipWidgetRouteRecovery(recovery, reason: "timeAdvanced")
          return
        }
        recovery.phase = .retryScheduled(
          waitingAt: waitingAt,
          routeChangeID: routeChangeID
        )
        widgetRouteRecovery = recovery
        scheduleWidgetRouteRecovery(recovery)
      case .requested, .routeChanged:
        skipWidgetRouteRecovery(recovery, reason: "noBufferEvaluation")
      case .retrying:
        failWidgetRouteRecovery(recovery, reason: "pausedAfterRetry")
      case .retryScheduled, .timingOut:
        break
      }
    case .playing:
      switch recovery.phase {
      case .waiting:
        skipWidgetRouteRecovery(recovery, reason: "resumedWithoutRetry")
      case .retryScheduled:
        skipWidgetRouteRecovery(recovery, reason: "resumedBeforeRetry")
      case .retrying:
        succeedWidgetRouteRecovery(recovery, reason: "playing")
      case .requested, .routeChanged, .timingOut:
        break
      }
    case .loading, .stopped:
      cancelWidgetRouteRecovery(reason: "playbackStateChanged")
    }
  }

  func handleWidgetRouteRecoveryProgress(_ event: PodAVPlayerEvent<CMTime>) {
    guard let recovery = widgetRouteRecovery else { return }
    guard recovery.playerSource == event.source else {
      cancelWidgetRouteRecovery(reason: "playerGenerationChanged")
      return
    }
    guard routeRecoveryHasProgressed(event.value, since: recovery.requestedTime) else { return }
    switch recovery.phase {
    case .retrying, .timingOut:
      succeedWidgetRouteRecovery(recovery, reason: "timeAdvanced")
    case .requested, .retryScheduled, .routeChanged, .waiting:
      cancelWidgetRouteRecovery(reason: "timeAdvanced")
    }
  }

  func cancelWidgetRouteRecovery(reason: String) {
    guard let recovery = widgetRouteRecovery else { return }
    widgetRouteRecoveryTask?.cancel()
    widgetRouteRecoveryTask = nil
    widgetRouteRecovery = nil
    Self.log.debug(
      """
      event=widgetRouteRecoveryCancelled reason=\(reason) requestID=\(recovery.requestID) \
      episodeID=\(recovery.episodeID) playerGeneration=\(recovery.playerSource.generation) \
      phase=\(routeRecoveryPhaseDescription(recovery.phase))
      """
    )
  }

  private func scheduleWidgetRouteRecovery(_ recovery: WidgetRouteRecovery) {
    guard case .retryScheduled = recovery.phase else { return }
    widgetRouteRecoveryTask?.cancel()
    Self.log.info(
      """
      event=widgetRouteRecoveryScheduled requestID=\(recovery.requestID) \
      episodeID=\(recovery.episodeID) playerGeneration=\(recovery.playerSource.generation) \
      phase=\(routeRecoveryPhaseDescription(recovery.phase))
      """
    )
    widgetRouteRecoveryTask = Task { @PlayActor [weak self] in
      guard let self else { return }
      do {
        try await sleeper.sleep(for: routeChangeRecoveryDelay)
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      widgetRouteRecoveryTask = nil
      await performWidgetRouteRecovery(requestID: recovery.requestID)
    }
  }

  private func performWidgetRouteRecovery(requestID: UUID) async {
    guard var recovery = widgetRouteRecovery, recovery.requestID == requestID,
      case .retryScheduled(let waitingAt, let routeChangeID) = recovery.phase
    else { return }
    let snapshot = await podAVPlayer.playbackSnapshot()
    guard sharedState.onDeck?.id == recovery.episodeID,
      snapshot.source == recovery.playerSource,
      snapshot.isFromCache,
      snapshot.status == .paused,
      !routeRecoveryHasProgressed(snapshot.currentTime, since: recovery.requestedTime)
    else {
      cancelWidgetRouteRecovery(reason: "retryOwnershipChanged")
      return
    }

    recovery.phase = .retrying(waitingAt: waitingAt, routeChangeID: routeChangeID)
    widgetRouteRecovery = recovery
    Self.log.notice(
      """
      event=widgetRouteRecoveryAttempt requestID=\(requestID) episodeID=\(recovery.episodeID) \
      playerGeneration=\(recovery.playerSource.generation) routeChangeID=\(routeChangeID) \
      currentTime=\(snapshot.currentTime) itemStatus=\(String(describing: snapshot.itemStatus)) \
      cached=\(snapshot.isFromCache) timeControlStatus=\(snapshot.status) \
      waitingReason=\(String(describing: snapshot.waitingReason))
      """
    )

    await podAVPlayer.play()
    guard let currentRecovery = widgetRouteRecovery, currentRecovery.requestID == requestID else {
      return
    }
    let result = await podAVPlayer.playbackSnapshot()
    switch result.status {
    case .playing:
      setStatus(.playing)
      succeedWidgetRouteRecovery(currentRecovery, reason: "playing")
    case .waiting:
      setStatus(.waiting)
      scheduleWidgetRouteRecoveryTimeout(currentRecovery)
    case .paused:
      setStatus(.paused)
      failWidgetRouteRecovery(currentRecovery, reason: "pausedAfterRetry")
    case .loading, .stopped:
      failWidgetRouteRecovery(currentRecovery, reason: "playbackStateChanged")
    }
  }

  private func scheduleWidgetRouteRecoveryTimeout(_ recovery: WidgetRouteRecovery) {
    guard case .retrying = recovery.phase else { return }
    widgetRouteRecoveryTask?.cancel()
    widgetRouteRecoveryTask = Task { @PlayActor [weak self] in
      guard let self else { return }
      do {
        try await sleeper.sleep(for: routeChangeRecoveryTimeout)
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      widgetRouteRecoveryTask = nil
      await timeOutWidgetRouteRecovery(requestID: recovery.requestID)
    }
  }

  private func timeOutWidgetRouteRecovery(requestID: UUID) async {
    guard var recovery = widgetRouteRecovery, recovery.requestID == requestID,
      case .retrying(let waitingAt, let routeChangeID) = recovery.phase
    else { return }
    let snapshot = await podAVPlayer.playbackSnapshot()
    guard sharedState.onDeck?.id == recovery.episodeID,
      snapshot.source == recovery.playerSource
    else {
      cancelWidgetRouteRecovery(reason: "timeoutOwnershipChanged")
      return
    }
    if snapshot.status == .playing
      || routeRecoveryHasProgressed(snapshot.currentTime, since: recovery.requestedTime)
    {
      succeedWidgetRouteRecovery(recovery, reason: "timeAdvanced")
      return
    }

    recovery.phase = .timingOut(waitingAt: waitingAt, routeChangeID: routeChangeID)
    widgetRouteRecovery = recovery
    await podAVPlayer.pause()
    setStatus(.paused)
    guard widgetRouteRecovery?.requestID == requestID else { return }
    failWidgetRouteRecovery(recovery, reason: "timeout")
  }

  private func skipWidgetRouteRecovery(_ recovery: WidgetRouteRecovery, reason: String) {
    widgetRouteRecoveryTask?.cancel()
    widgetRouteRecoveryTask = nil
    widgetRouteRecovery = nil
    Self.log.debug(
      """
      event=widgetRouteRecoverySkipped reason=\(reason) requestID=\(recovery.requestID) \
      episodeID=\(recovery.episodeID) playerGeneration=\(recovery.playerSource.generation) \
      phase=\(routeRecoveryPhaseDescription(recovery.phase)) cached=\(recovery.isFromCache)
      """
    )
  }

  private func succeedWidgetRouteRecovery(_ recovery: WidgetRouteRecovery, reason: String) {
    widgetRouteRecoveryTask?.cancel()
    widgetRouteRecoveryTask = nil
    widgetRouteRecovery = nil
    Self.log.notice(
      """
      event=widgetRouteRecoverySucceeded reason=\(reason) requestID=\(recovery.requestID) \
      episodeID=\(recovery.episodeID) playerGeneration=\(recovery.playerSource.generation)
      """
    )
  }

  private func failWidgetRouteRecovery(_ recovery: WidgetRouteRecovery, reason: String) {
    widgetRouteRecoveryTask?.cancel()
    widgetRouteRecoveryTask = nil
    widgetRouteRecovery = nil
    setStatus(.paused)
    Self.log.warning(
      """
      event=widgetRouteRecoveryFailed reason=\(reason) requestID=\(recovery.requestID) \
      episodeID=\(recovery.episodeID) playerGeneration=\(recovery.playerSource.generation)
      """
    )
  }

  private func routeRecoveryHasProgressed(_ time: CMTime, since startTime: CMTime) -> Bool {
    time.seconds - startTime.seconds > routeChangeProgressTolerance
  }

  private func routeRecoveryPhaseDescription(_ phase: WidgetRouteRecovery.Phase) -> String {
    switch phase {
    case .requested:
      "requested"
    case .retrying:
      "retrying"
    case .retryScheduled:
      "retryScheduled"
    case .routeChanged:
      "routeChanged"
    case .timingOut:
      "timingOut"
    case .waiting:
      "waiting"
    }
  }
}
