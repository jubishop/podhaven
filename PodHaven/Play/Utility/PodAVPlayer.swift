// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import Logging
import Tagged

extension Container {
  @MainActor var podAVPlayer: Factory<PodAVPlayer> {
    Factory(self) { PodAVPlayer() }.scope(.cached)
  }

  var loadEpisodeAsset: Factory<(_ asset: AVURLAsset) async throws -> EpisodeAsset> {
    Factory(self) {
      { asset in
        let (isPlayable, duration) = try await asset.load(.isPlayable, .duration)
        return await EpisodeAsset(
          isPlayable: isPlayable,
          duration: duration.safe,
          playerItemFactory: { AVPlayerItem(asset: asset) }
        )
      }
    }
  }
}

enum PodAVPlayerError: Error, LocalizedError {
  case notPlayable(Episode.ID, details: String)
  case episodeNotFoundAfterUpdate(Episode.ID, details: String)

  var errorDescription: String? {
    switch self {
    case .notPlayable(let id, let details):
      return "Episode \(id) media is not playable\n\(details)"
    case .episodeNotFoundAfterUpdate(let id, let details):
      return "Episode \(id) not found after duration update\n\(details)"
    }
  }
}

struct PodAVPlayerEventSource: Equatable, Sendable {
  let episodeID: Episode.ID
  let itemIdentity: ObjectIdentifier
  let generation: UUID
}

struct PodAVPlayerEvent<Value: Sendable>: Sendable {
  let source: PodAVPlayerEventSource
  let value: Value
}

struct PodAVPlayerPlaybackSnapshot {
  let currentTime: CMTime
  let episodeID: Episode.ID?
  let isFromCache: Bool
  let itemStatus: AVPlayerItem.Status?
  let source: PodAVPlayerEventSource?
  let status: PlaybackStatus
  let waitingReason: String?
}

@MainActor class PodAVPlayer {
  @DynamicInjected(\.avPlayer) private var avPlayer
  @DynamicInjected(\.cacheFileStore) private var cacheFileStore
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.loadEpisodeAsset) private var loadEpisodeAsset
  @DynamicInjected(\.notifications) private var notifications
  @DynamicInjected(\.repo) private var repo

  // Cadence at which playback ticks reach the database. Downstream consumers
  // (notably `PlaybackCoverage`'s bitmap) align their chunk width to this
  // value so each tick lands on a chunk boundary.
  nonisolated static let playbackTickSeconds: Int = 3

  nonisolated private static let log = Log.as(LogSubsystem.Play.avPlayer)

  // MARK: - State Management

  private var episodeID: Episode.ID?
  private var eventSource: PodAVPlayerEventSource?
  private var lastDatabaseUpdateTime: CMTime?
  private var latestSeekID: UUID?

  private var playingFromCache: Bool {
    guard let urlAsset = avPlayer.current?.asset as? AVURLAsset
    else { return false }
    return urlAsset.url.isFileURL
  }

  let currentTimeStream: AsyncStream<PodAVPlayerEvent<CMTime>>
  let itemStatusStream: AsyncStream<PodAVPlayerEvent<AVPlayerItem.Status>>
  let controlStatusStream: AsyncStream<PodAVPlayerEvent<PlaybackStatus>>
  let rateStream: AsyncStream<PodAVPlayerEvent<Float>>
  let didPlayToEndStream: AsyncStream<PodAVPlayerEventSource>

  private let currentTimeContinuation: AsyncStream<PodAVPlayerEvent<CMTime>>.Continuation
  private let itemStatusContinuation:
    AsyncStream<PodAVPlayerEvent<AVPlayerItem.Status>>.Continuation
  private let controlStatusContinuation: AsyncStream<PodAVPlayerEvent<PlaybackStatus>>.Continuation
  private let rateContinuation: AsyncStream<PodAVPlayerEvent<Float>>.Continuation
  private let didPlayToEndContinuation: AsyncStream<PodAVPlayerEventSource>.Continuation

  private var periodicTimeObservation: (observer: Any, player: any AVPlayable)?
  private var itemStatusObserver: NSKeyValueObservation?
  private var timeControlStatusObserver: NSKeyValueObservation?
  private var rateObserver: NSKeyValueObservation?
  private var didPlayToEndTask: Task<Void, Never>?

  // MARK: - Initialization

  fileprivate init() {
    (currentTimeStream, currentTimeContinuation) = AsyncStream.makeStream(
      of: PodAVPlayerEvent<CMTime>.self
    )
    (itemStatusStream, itemStatusContinuation) = AsyncStream.makeStream(
      of: PodAVPlayerEvent<AVPlayerItem.Status>.self
    )
    (controlStatusStream, controlStatusContinuation) = AsyncStream.makeStream(
      of: PodAVPlayerEvent<PlaybackStatus>.self
    )
    (rateStream, rateContinuation) = AsyncStream.makeStream(
      of: PodAVPlayerEvent<Float>.self
    )
    (didPlayToEndStream, didPlayToEndContinuation) = AsyncStream.makeStream(
      of: PodAVPlayerEventSource.self
    )
  }

  // MARK: - Loading

  func load(_ podcastEpisode: PodcastEpisode) async throws -> PodcastEpisode {
    Self.log.debug("load: \(podcastEpisode.toString)")

    let (podcastEpisode, playableItem) = try await loadAsset(for: podcastEpisode)
    try Task.checkCancellation()
    lastDatabaseUpdateTime = podcastEpisode.currentTime
    bind(playableItem, to: podcastEpisode.id)

    return podcastEpisode
  }

  private func bind(_ playableItem: any AVPlayableItem, to episodeID: Episode.ID) {
    self.episodeID = episodeID
    eventSource = PodAVPlayerEventSource(
      episodeID: episodeID,
      itemIdentity: ObjectIdentifier(playableItem),
      generation: UUID()
    )
    avPlayer.replaceCurrent(with: playableItem)
  }

  private func loadAsset(for podcastEpisode: PodcastEpisode) async throws
    -> (podcastEpisode: PodcastEpisode, playableItem: any AVPlayableItem)
  {
    Self.log.debug("loadAsset: \(podcastEpisode.toString)")

    let episodeAsset: EpisodeAsset = try await performLoadAsset(for: podcastEpisode)

    guard episodeAsset.isPlayable else {
      throw PodAVPlayerError.notPlayable(
        podcastEpisode.id,
        details:
          """
          PodcastEpisode: 
            \(podcastEpisode.toString), 
            MediaGUID: \(podcastEpisode.episode.unsaved.id)
          """
      )
    }

    try await repo.updateDuration(podcastEpisode.id, duration: episodeAsset.duration)
    guard let updatedPodcastEpisode = try await repo.podcastEpisode(podcastEpisode.id) else {
      throw PodAVPlayerError.episodeNotFoundAfterUpdate(
        podcastEpisode.id,
        details: "PodcastEpisode: \(podcastEpisode.toString)"
      )
    }

    return (updatedPodcastEpisode, episodeAsset.playerItem())
  }
  private func performLoadAsset(for podcastEpisode: PodcastEpisode) async throws
    -> EpisodeAsset
  {
    guard let cachedURL = podcastEpisode.episode.cachedURL else {
      Self.log.debug("performLoadAsset: loading from remote (no cache)")
      return try await loadEpisodeAsset(
        AVURLAsset(url: podcastEpisode.episode.mediaURL.rawValue)
      )
    }
    do {
      Self.log.debug("performLoadAsset: loading from cache: \(cachedURL)")
      return try await loadEpisodeAsset(AVURLAsset(url: cachedURL.rawValue))
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      try Task.checkCancellation()
      Self.log.caughtError(
        "performLoadAsset: cache load failed, discarding invalid cache and falling back to remote",
        error,
        level: .warning
      )
      do {
        try await cacheFileStore.discardInvalidFile(
          for: podcastEpisode.id,
          cachedFilename: cachedURL.lastPathComponent
        )
      } catch {
        Self.log.caughtError(
          "performLoadAsset: failed to discard invalid cache for \(podcastEpisode.toString)",
          error
        )
      }
      do {
        try await cacheManager.downloadToCache(for: podcastEpisode.id)
        Self.log.info("performLoadAsset: re-queued cache download for \(podcastEpisode.toString)")
      } catch {
        Self.log.caughtError(
          "performLoadAsset: failed to re-queue cache download for \(podcastEpisode.toString)",
          error
        )
      }
      return try await loadEpisodeAsset(
        AVURLAsset(url: podcastEpisode.episode.mediaURL.rawValue)
      )
    }
  }

  func clear() {
    Self.log.debug("clear: executing")
    removeObservers()
    episodeID = nil
    eventSource = nil
    lastDatabaseUpdateTime = nil
    latestSeekID = nil
    avPlayer.replaceCurrent(with: nil)
  }

  func currentTime() -> CMTime {
    avPlayer.currentTime()
  }

  func playbackStatus() -> PlaybackStatus {
    PlaybackStatus(avPlayer.timeControlStatus)
  }

  func reasonForWaitingToPlay() -> String? {
    avPlayer.reasonForWaitingToPlay?.rawValue
  }

  func playbackSnapshot() -> PodAVPlayerPlaybackSnapshot {
    PodAVPlayerPlaybackSnapshot(
      currentTime: avPlayer.currentTime(),
      episodeID: episodeID,
      isFromCache: playingFromCache,
      itemStatus: avPlayer.current?.status,
      source: eventSource,
      status: PlaybackStatus(avPlayer.timeControlStatus),
      waitingReason: avPlayer.reasonForWaitingToPlay?.rawValue
    )
  }

  func isCurrentItem(_ item: AVPlayerItem?) -> Bool {
    guard let item, let current = avPlayer.current as? AVPlayerItem
    else { return false }
    return item === current
  }

  func isCurrent(_ source: PodAVPlayerEventSource) -> Bool {
    guard eventSource == source, let currentItem = avPlayer.current else { return false }
    return ObjectIdentifier(currentItem) == source.itemIdentity
  }

  // Swap to cached version if available. Returns whether a swap occurred.
  // Note: We don't bother throwing here, just return false for any failure.
  @discardableResult
  private func swapToCached(from source: PodAVPlayerEventSource) async -> Bool {
    guard isCurrent(source), !playingFromCache else { return false }
    let episodeID = source.episodeID

    let podcastEpisode: PodcastEpisode
    do {
      guard let fetched = try await repo.podcastEpisode(episodeID) else { return false }
      podcastEpisode = fetched
    } catch {
      Self.log.caughtError(
        "swapToCached: failed to fetch episode \(episodeID)",
        error
      )
      return false
    }
    guard isCurrent(source) else {
      Self.log.debug("swapToCached: source retired while fetching episode \(episodeID)")
      return false
    }

    guard podcastEpisode.episode.cachedURL != nil else { return false }

    let playableItem: any AVPlayableItem
    do {
      (_, playableItem) = try await loadAsset(for: podcastEpisode)
    } catch {
      Self.log.caughtError(
        "swapToCached: failed to load cached asset for \(podcastEpisode.toString)",
        error
      )
      return false
    }
    guard isCurrent(source) else {
      Self.log.debug("swapToCached: source retired while loading cached item for \(episodeID)")
      return false
    }

    removeObservers()
    bind(playableItem, to: episodeID)
    addObservers()
    Self.log.info("swapToCached: swapped to cached version")
    return true
  }

  // MARK: - Playback Controls

  func play() {
    Self.log.debug("play: executing (fromCache: \(playingFromCache))")
    avPlayer.play()
  }

  func pause() async {
    Self.log.debug("pause: executing")
    avPlayer.pause()
    await savePosition()
  }

  func savePosition() async {
    await saveCurrentTime(avPlayer.currentTime())
  }

  func toggle() async {
    let currentStatus = avPlayer.timeControlStatus
    Self.log.debug("toggle: executing (current status: \(currentStatus))")

    if currentStatus == .paused {
      play()
    } else if currentStatus == .playing {
      await pause()
    } else {
      Self.log.warning("Calling toggle when current status is: \(currentStatus)")
    }
  }

  func setRate(_ rate: Float) {
    Self.log.debug("setRate: \(rate)")

    avPlayer.setDefaultRate(rate)
    if avPlayer.timeControlStatus != .paused {
      Self.log.debug("Setting rate because timeControlStatus is: \(avPlayer.timeControlStatus)")
      avPlayer.setRate(rate)
    }
  }

  // MARK: - Seeking

  func seek(to time: CMTime) async {
    Self.log.debug("seek: \(time)")
    guard let seekingEpisodeID = episodeID else {
      Self.log.debug("seek: ignored with no episode")
      return
    }

    guard let seekingSource = eventSource else { return }
    let seekID = UUID()
    latestSeekID = seekID
    await swapToCached(from: seekingSource)
    guard latestSeekID == seekID, episodeID == seekingEpisodeID else { return }
    guard let eventSource else { return }

    removePeriodicTimeObserver()
    currentTimeContinuation.yield(PodAVPlayerEvent(source: eventSource, value: time))

    avPlayer.seek(to: time) { [weak self, eventSource, seekID] completed in
      guard let self else { return }

      if completed {
        Self.log.debug("seek: to \(time) completed")
        Task { @MainActor [weak self, eventSource, seekID] in
          guard let self, self.latestSeekID == seekID, self.isCurrent(eventSource) else { return }
          await self.saveCurrentTime(time)
          guard self.latestSeekID == seekID, self.isCurrent(eventSource) else { return }
          self.addPeriodicTimeObserver()
        }
      } else {
        Self.log.debug("seek: to \(time) interrupted")
      }
    }
  }

  private func saveCurrentTime(_ currentTime: CMTime) async {
    guard let episodeID else {
      Self.log.debug("Setting current time on nil player item with CMTime: \(currentTime)")
      return
    }

    do {
      try await repo.updateCurrentTime(episodeID, currentTime: currentTime)
      guard self.episodeID == episodeID else { return }
      lastDatabaseUpdateTime = currentTime
      Self.log.trace("saveCurrentTime: saved \(currentTime) for \(episodeID)")
    } catch {
      Self.log.caughtError(
        "saveCurrentTime: failed to save time \(currentTime) for episode \(episodeID)",
        error
      )
    }
  }

  // Seek and pause stay on `saveCurrentTime` — they don't represent content
  // the user actually heard, so the bitmap and `lastPlayedDate` shouldn't grow.
  private func savePlaybackTick(_ currentTime: CMTime, episodeID: Episode.ID) async {
    guard self.episodeID == episodeID else { return }
    let playedFrom = lastDatabaseUpdateTime ?? currentTime
    do {
      try await repo.updatePlayback(
        episodeID,
        currentTime: currentTime,
        playedFrom: playedFrom,
        now: Date()
      )
      guard self.episodeID == episodeID else { return }
      lastDatabaseUpdateTime = currentTime
      Self.log.trace(
        "savePlaybackTick: saved \(currentTime) (from \(playedFrom)) for \(episodeID)"
      )
    } catch {
      Self.log.caughtError(
        "savePlaybackTick: failed to save \(currentTime) for episode \(episodeID)",
        error
      )
    }
  }

  // MARK: - Change Handlers

  private func handleCurrentTimeChange(
    _ currentTime: CMTime,
    source: PodAVPlayerEventSource
  ) async {
    guard isCurrent(source) else { return }

    // `abs` guards against any future path that moves time backward without
    // routing through `seek(to:)` (which resets `lastDatabaseUpdateTime`).
    if abs(currentTime.seconds - (lastDatabaseUpdateTime ?? .zero).seconds)
      >= Double(Self.playbackTickSeconds)
    {
      await savePlaybackTick(currentTime, episodeID: source.episodeID)
      guard isCurrent(source) else { return }
    }

    // Always yield to the stream for UI updates (250ms)
    Self.log.trace("handleCurrentTimeChange to: \(currentTime) for \(source.episodeID)")
    currentTimeContinuation.yield(PodAVPlayerEvent(source: source, value: currentTime))
  }

  // MARK: - Transient State Tracking

  func addObservers() {
    addItemStatusObserver()
    addPeriodicTimeObserver()
    addTimeControlStatusObserver()
    addRateObserver()
    addDidPlayToEndObserver()
  }

  func removeObservers() {
    removeItemStatusObserver()
    removePeriodicTimeObserver()
    removeTimeControlStatusObserver()
    removeRateObserver()
    removeDidPlayToEndObserver()
  }

  private func addItemStatusObserver() {
    guard itemStatusObserver == nil else { return }

    guard let currentItem = avPlayer.current, let eventSource else { return }
    let avPlayerItem = currentItem as? AVPlayerItem
    itemStatusObserver = currentItem.observeStatus(options: [.initial, .new]) {
      [weak self, avPlayerItem, eventSource] status in
      guard let self else { return }

      switch status {
      case .unknown:
        Self.log.debug("AVPlayerItem status: unknown for episode \(eventSource.episodeID)")
      case .readyToPlay:
        Self.log.debug("AVPlayerItem status: readyToPlay for episode \(eventSource.episodeID)")
      case .failed:
        if let error = avPlayerItem?.error {
          Self.log.caughtError(
            "AVPlayerItem status: failed for episode \(eventSource.episodeID)",
            error
          )
        } else {
          Self.log.error(
            """
            AVPlayerItem status: failed for episode \(eventSource.episodeID) \
            (no error details)
            """
          )
        }
      @unknown default:
        Self.log.warning("AVPlayerItem status: unknown value (\(status.rawValue))")
      }

      itemStatusContinuation.yield(PodAVPlayerEvent(source: eventSource, value: status))
    }
  }

  private func addPeriodicTimeObserver() {
    guard periodicTimeObservation == nil else { return }
    guard let eventSource else { return }

    Self.log.debug("addPeriodicTimeObserver: registering using player's internal queue")
    let observer = avPlayer.addPeriodicTimeObserver(
      forInterval: .milliseconds(250),
      queue: nil
    ) { [weak self, eventSource] currentTime in
      guard let self else { return }
      Task { [weak self, currentTime, eventSource] in
        guard let self else { return }
        await self.handleCurrentTimeChange(currentTime, source: eventSource)
      }
    }
    periodicTimeObservation = (observer, avPlayer)
  }

  private func addTimeControlStatusObserver() {
    guard timeControlStatusObserver == nil else { return }
    guard let eventSource else { return }

    timeControlStatusObserver = avPlayer.observeTimeControlStatus(options: [.initial, .new]) {
      [weak self, eventSource] status in
      guard let self else { return }
      controlStatusContinuation.yield(
        PodAVPlayerEvent(source: eventSource, value: PlaybackStatus(status))
      )

      Task { @MainActor [weak self, eventSource] in
        guard let self, self.isCurrent(eventSource) else { return }
        let snapshot = playbackSnapshot()
        Self.log.debug(
          """
          event=playerTimeControlStatus episodeID=\(eventSource.episodeID) \
          playerGeneration=\(eventSource.generation) status=\(PlaybackStatus(status)) \
          currentTime=\(snapshot.currentTime) itemStatus=\(String(describing: snapshot.itemStatus)) \
          cached=\(snapshot.isFromCache) \
          waitingReason=\(String(describing: snapshot.waitingReason))
          """
        )
        guard status != .playing else { return }
        let currentTime = avPlayer.currentTime()
        if await swapToCached(from: eventSource) {
          avPlayer.seek(to: currentTime)
        }
      }
    }
  }

  private func addRateObserver() {
    guard rateObserver == nil else { return }
    guard let eventSource else { return }

    rateObserver = avPlayer.observeRate(options: [.initial, .new]) {
      [weak self, eventSource] rate in
      guard let self else { return }
      Self.log.debug("rate changed: \(rate)")
      rateContinuation.yield(PodAVPlayerEvent(source: eventSource, value: rate))
    }
  }

  private func removeItemStatusObserver() {
    if itemStatusObserver != nil {
      self.itemStatusObserver = nil
    }
  }

  private func removePeriodicTimeObserver() {
    if let (observer, player) = periodicTimeObservation {
      Self.log.debug("removePeriodicTimeObserver: unregistering observer")
      player.removeTimeObserver(observer)
      periodicTimeObservation = nil
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

  private func addDidPlayToEndObserver() {
    guard didPlayToEndTask == nil else { return }
    guard let eventSource else { return }

    didPlayToEndTask = Task { [weak self, eventSource] in
      guard let self else { return }
      for await notification in notifications(AVPlayerItem.didPlayToEndTimeNotification) {
        guard !Task.isCancelled else { return }
        guard let item = notification.object as? any AVPlayableItem else {
          Self.log.warning("Ignoring didPlayToEndTimeNotification without a player item")
          continue
        }
        guard ObjectIdentifier(item) == eventSource.itemIdentity else {
          Self.log.debug(
            """
            Ignoring didPlayToEndTimeNotification from non-current item for episode \
            \(eventSource.episodeID)
            """
          )
          continue
        }
        didPlayToEndContinuation.yield(eventSource)
      }
    }
  }

  private func removeDidPlayToEndObserver() {
    if let didPlayToEndTask {
      didPlayToEndTask.cancel()
      self.didPlayToEndTask = nil
    }
  }
}

// MARK: - PlaybackStatus + AVPlayer

extension PlaybackStatus {
  init(_ timeControlStatus: AVPlayer.TimeControlStatus) {
    switch timeControlStatus {
    case .paused:
      self = .paused
    case .playing:
      self = .playing
    case .waitingToPlayAtSpecifiedRate:
      self = .waiting
    @unknown default:
      Assert.fatal("Unknown time control status: \(timeControlStatus)")
    }
  }
}
