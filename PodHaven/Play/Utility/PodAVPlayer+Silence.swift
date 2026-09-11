// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Foundation
import GRDB
import Logging
import Tagged

@MainActor struct SilencePlaybackState {
  enum Pending { case cut, preparation, replacement }
  var content: CachedAudioContent?
  var map: SilenceMap?
  var consumedInterval: Int?
  var pending: Pending?
  var replacementIntent: PlaybackStatus?
  var streamingFallback: (any AVPlayableItem)?
  var boundary: (token: Any, player: any AVPlayable)?
  var observations: [Task<Void, Never>] = []
}

extension PodAVPlayer {
  func startSilenceObservation() {
    guard silenceState.observations.isEmpty, let source = eventSource else { return }
    let state = Container.shared.sharedState()
    let settings = Container.shared.userSettings()
    let store = Container.shared.silenceStore()
    if let content = silenceState.content {
      silenceState.observations.append(
        Task { [weak self] in
          do {
            for try await observed in store.observeContent(for: content.filename) {
              guard let self, !Task.isCancelled, self.isCurrent(source) else { return }
              if let observed, observed.generation == content.generation {
                self.silenceState.map = try observed.map
              } else {
                self.silenceState.map = nil
                if self.silenceState.pending != .replacement { self.cancelAutomaticSilenceWork() }
              }
              await self.updateSilencePlayback()
            }
          } catch {
            guard let self, self.isCurrent(source) else { return }
            self.silenceState.map = nil
            if self.silenceState.pending != .replacement { self.cancelAutomaticSilenceWork() }
            Self.log.caughtError("Silence map observation failed", error)
          }
        }
      )
    }
    silenceState.observations.append(
      Task { [weak self] in
        for await _ in settings.$silenceMode.stream() {
          guard let self, !Task.isCancelled, self.isCurrent(source) else { return }
          await self.updateSilencePlayback()
        }
      }
    )
    silenceState.observations.append(
      Task { [weak self] in
        for await _ in state.$silenceOverride.stream() {
          guard let self, !Task.isCancelled, self.isCurrent(source) else { return }
          await self.updateSilencePlayback()
        }
      }
    )
    silenceState.observations.append(
      Task { [weak self] in
        var previousMode: SilenceMode?
        var previousCache: Episode.CacheStatus?
        for await onDeck in state.$onDeck.stream() {
          guard let self, !Task.isCancelled, self.isCurrent(source) else { return }
          guard onDeck?.id == source.episodeID else { continue }
          guard previousMode != onDeck?.silenceMode || previousCache != onDeck?.cacheStatus else {
            continue
          }
          previousMode = onDeck?.silenceMode
          previousCache = onDeck?.cacheStatus
          await self.updateSilencePlayback()
        }
      }
    )
  }

  func stopSilenceObservation() {
    for observation in silenceState.observations { observation.cancel() }
    silenceState.observations = []
    cancelAutomaticSilenceWork()
    removeSilenceBoundary()
  }

  func cancelAutomaticSilenceWork() {
    guard silenceState.pending != nil else { return }
    silenceState.pending = nil
    silenceState.streamingFallback = nil
    latestSeekID = nil
    avPlayer.cancelPendingSeeks()
    lastDatabaseUpdateTime = avPlayer.currentTime()
    addPeriodicTimeObserver()
    removeSilenceBoundary()
  }

  func updateSilencePlayback() async {
    let state = Container.shared.sharedState()
    if state.effectiveSilenceMode == .off {
      if silenceState.pending != .replacement { cancelAutomaticSilenceWork() }
      removeSilenceBoundary()
      return
    }
    if !playbackSnapshot().isFromCache, state.onDeck?.cacheStatus == .cached {
      await activateCachedSilence()
    }
    refreshSilenceBoundary()
    await shortenSilenceIfNeeded()
  }

  func refreshSilenceBoundary() {
    removeSilenceBoundary()
    let state = Container.shared.sharedState()
    guard state.effectiveSilenceMode != .off, latestSeekID == nil,
      avPlayer.timeControlStatus == .playing,
      let map = silenceState.map, let source = eventSource
    else { return }
    let policy = SilencePolicy(mode: state.effectiveSilenceMode, rate: Double(selectedRate))
    let now = avPlayer.currentTime().seconds
    guard
      let interval = map.intervals.first(where: {
        $0.start + policy.padding > now && $0.end - $0.start >= policy.minimumGap
      })
    else { return }
    let token = avPlayer.addBoundaryTimeObserver(
      forTimes: [
        NSValue(time: CMTime(seconds: interval.start + policy.padding, preferredTimescale: 600_000))
      ],
      queue: nil
    ) { [weak self] in
      Task { @MainActor [weak self] in
        guard let self, self.isCurrent(source) else { return }
        await self.shortenSilenceIfNeeded()
        self.refreshSilenceBoundary()
      }
    }
    silenceState.boundary = (token, avPlayer)
  }

  private func removeSilenceBoundary() {
    guard let boundary = silenceState.boundary else { return }
    boundary.player.removeTimeObserver(boundary.token)
    silenceState.boundary = nil
  }

  @discardableResult
  func shortenSilenceIfNeeded() async -> Bool {
    let state = Container.shared.sharedState()
    guard state.effectiveSilenceMode != .off, !state.playbackStatus.loading, latestSeekID == nil,
      avPlayer.timeControlStatus == .playing, avPlayer.current?.status == .readyToPlay,
      let source = eventSource, let content = silenceState.content, let map = silenceState.map,
      playbackSnapshot().isFromCache, periodicTimeObservation != nil
    else { return false }
    let time = avPlayer.currentTime().seconds
    var lower = 0
    var upper = map.intervals.count
    while lower < upper {
      let middle = lower + (upper - lower) / 2
      if map.intervals[middle].end <= time { lower = middle + 1 } else { upper = middle }
    }
    guard lower < map.intervals.count, silenceState.consumedInterval != lower else { return false }
    let interval = map.intervals[lower]
    let policy = SilencePolicy(mode: state.effectiveSilenceMode, rate: Double(selectedRate))
    guard policy.cut(in: interval, from: time) != nil else { return false }
    let id = UUID()
    latestSeekID = id
    silenceState.pending = .cut
    do {
      let current = try await Container.shared.silenceStore().isCurrent(content)
      guard latestSeekID == id, isCurrent(source) else { return true }
      guard current else {
        silenceState.map = nil
        cancelAutomaticSilenceWork()
        return false
      }
    } catch {
      Self.log.caughtError("Could not validate silence source", error)
      guard latestSeekID == id, isCurrent(source) else { return true }
      cancelAutomaticSilenceWork()
      return false
    }
    guard latestSeekID == id, isCurrent(source) else { return true }
    guard state.effectiveSilenceMode != .off, avPlayer.timeControlStatus == .playing else {
      cancelAutomaticSilenceWork()
      return false
    }
    let heardThrough = avPlayer.currentTime()
    let saved = await savePlaybackTick(heardThrough, episodeID: source.episodeID)
    guard latestSeekID == id, isCurrent(source) else { return true }
    guard saved else {
      cancelAutomaticSilenceWork()
      return false
    }
    guard latestSeekID == id, isCurrent(source) else { return true }
    let currentPolicy = SilencePolicy(mode: state.effectiveSilenceMode, rate: Double(selectedRate))
    guard avPlayer.timeControlStatus == .playing,
      let target = currentPolicy.cut(in: interval, from: avPlayer.currentTime().seconds)
    else {
      cancelAutomaticSilenceWork()
      return false
    }
    silenceState.consumedInterval = lower
    removePeriodicTimeObserver()
    removeSilenceBoundary()
    avPlayer.seek(
      to: CMTime(seconds: target, preferredTimescale: 600_000),
      toleranceBefore: .zero,
      toleranceAfter: .zero
    ) {
      [weak self] completed in
      Task { @MainActor [weak self] in
        guard let self, self.latestSeekID == id, self.isCurrent(source) else { return }
        let actual = self.avPlayer.currentTime()
        self.lastDatabaseUpdateTime = actual
        await self.saveCurrentTime(actual)
        guard self.latestSeekID == id, self.isCurrent(source) else { return }
        self.latestSeekID = nil
        self.silenceState.pending = nil
        self.currentTimeContinuation.yield(PodAVPlayerEvent(source: source, value: actual))
        self.addPeriodicTimeObserver()
        self.refreshSilenceBoundary()
        Self.log.debug("Automatic silence seek completed=\(completed) actual=\(actual.seconds)")
      }
    }
    return true
  }

  private func activateCachedSilence() async {
    guard let source = eventSource, latestSeekID == nil,
      avPlayer.timeControlStatus != .waitingToPlayAtSpecifiedRate,
      !Container.shared.sharedState().playbackStatus.loading
    else { return }
    let id = UUID()
    latestSeekID = id
    silenceState.pending = .preparation
    do {
      guard let episode = try await Container.shared.repo().podcastEpisode(source.episodeID),
        episode.episode.cachedURL != nil
      else {
        cancelAutomaticSilenceWork()
        return
      }
      guard await permitsAutomaticCacheReplacement(episode) else {
        if latestSeekID == id { cancelAutomaticSilenceWork() }
        return
      }
      let (_, item, content) = try await loadAsset(for: episode, mediaServicesResetElapsed: nil)
      guard latestSeekID == id, isCurrent(source) else { return }
      guard let content, Container.shared.sharedState().effectiveSilenceMode != .off else {
        cancelAutomaticSilenceWork()
        return
      }
      guard let streamingItem = avPlayer.current else { return }
      let time = avPlayer.currentTime()
      guard await savePlaybackTick(time, episodeID: source.episodeID),
        latestSeekID == id, isCurrent(source)
      else {
        if latestSeekID == id { cancelAutomaticSilenceWork() }
        return
      }
      silenceState.replacementIntent = PlaybackStatus(avPlayer.timeControlStatus)
      silenceState.pending = nil
      removeObservers()
      avPlayer.pause()
      bind(item, to: source.episodeID, content: content)
      guard let replacementSource = eventSource else { return }
      latestSeekID = id
      silenceState.pending = .replacement
      addObservers()
      removePeriodicTimeObserver()
      positionSilenceReplacement(
        at: time,
        source: replacementSource,
        id: id,
        streamingFallback: streamingItem
      )
    } catch {
      Self.log.caughtError("Could not activate cached silence playback", error)
      if latestSeekID == id { cancelAutomaticSilenceWork() }
    }
  }

  func permitsAutomaticCacheReplacement(_ episode: PodcastEpisode) async -> Bool {
    guard let rejected = Container.shared.sharedState().silenceSourceRejection,
      rejected.episodeID == episode.id,
      rejected.filename == episode.episode.cachedURL?.lastPathComponent
    else { return true }
    do {
      let current = try await Container.shared.silenceStore().content(for: rejected.filename)
      return current?.generation != rejected.generation
    } catch {
      Self.log.caughtError("Could not validate previously rejected cache replacement", error)
      return false
    }
  }

  private func positionSilenceReplacement(
    at time: CMTime,
    source: PodAVPlayerEventSource,
    id: UUID,
    streamingFallback: (any AVPlayableItem)?
  ) {
    silenceState.streamingFallback = streamingFallback
    avPlayer.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) {
      [weak self] completed in
      Task { @MainActor [weak self] in
        guard let self, self.latestSeekID == id, self.isCurrent(source) else { return }
        if !completed, let streamingFallback = self.silenceState.streamingFallback {
          if let content = self.silenceState.content {
            Container.shared.sharedState().$silenceSourceRejection
              .new(
                SilenceSourceRejection(
                  episodeID: source.episodeID,
                  filename: content.filename,
                  generation: content.generation
                )
              )
          }
          Self.log.error(
            "Cached position restoration failed; restoring streaming at \(time.seconds)"
          )
          self.silenceState.pending = nil
          self.removeObservers()
          self.bind(streamingFallback, to: source.episodeID, content: nil)
          guard let restoredSource = self.eventSource else { return }
          self.latestSeekID = id
          self.silenceState.pending = .replacement
          self.addObservers()
          self.removePeriodicTimeObserver()
          self.positionSilenceReplacement(
            at: time,
            source: restoredSource,
            id: id,
            streamingFallback: nil
          )
          return
        }
        if !completed {
          self.silenceState.replacementIntent = .paused
          Self.log.error(
            "Streaming position restoration failed at \(time.seconds); playback paused"
          )
          Container.shared.alert()("Could not restore the playback position. Playback is paused.")
        }
        let actual = self.avPlayer.currentTime()
        self.lastDatabaseUpdateTime = actual
        await self.saveCurrentTime(actual)
        guard self.latestSeekID == id, self.isCurrent(source) else { return }
        self.latestSeekID = nil
        self.silenceState.pending = nil
        self.silenceState.streamingFallback = nil
        self.currentTimeContinuation.yield(PodAVPlayerEvent(source: source, value: actual))
        self.addPeriodicTimeObserver()
        self.finishSilenceReplacementIntent()
        self.refreshSilenceBoundary()
        await self.shortenSilenceIfNeeded()
      }
    }
  }

  func finishSilenceReplacementIntent() {
    guard let intent = silenceState.replacementIntent else { return }
    silenceState.replacementIntent = nil
    setRate(selectedRate)
    if intent == .playing { avPlayer.play() } else { avPlayer.pause() }
  }
}
