// Copyright Justin Bishop, 2024

import AVFoundation
import Foundation
import Semaphore

struct PlayManagerAccessKey { fileprivate init() {} }

@globalActor
final actor PlayActor: Sendable { static let shared = PlayActor() }

@PlayActor final class PlayManager: Sendable {
  static let shared = PlayManager()

  // MARK: - Static Methods

  private static var audioSession: AVAudioSession {
    AVAudioSession.sharedInstance()
  }

  static func configureAudioSession() async {
    do {
      try audioSession.setCategory(
        .playback,
        mode: .spokenAudio,
        policy: .longFormAudio
      )
      try audioSession.setMode(.spokenAudio)
      try await shared.resume()
    } catch {
      await Alert.shared("Failed to set the audio session configuration")
    }
  }

  // MARK: - State Management

  private let accessKey = PlayManagerAccessKey()
  private var _status: PlayState.Status = .stopped
  private var status: PlayState.Status {
    get { _status }
    set {
      guard newValue != _status else { return }
      _status = newValue
      nowPlayingInfo?.status = newValue
      Task { @MainActor in PlayState.shared.setStatus(newValue, accessKey) }
    }
  }
  private var avPlayer = AVPlayer()
  private var avPlayerItem = AVPlayerItem(url: URL.placeholder)
  private var nowPlayingInfo: NowPlayingInfo?
  private var commandCenter: CommandCenter
  private let loadingSemaphor = AsyncSemaphore(value: 1)
  private var commandObservingTask: Task<Void, Never>?
  private var interruptionObservingTask: Task<Void, Never>?
  private var keyValueObservers = [NSKeyValueObservation](capacity: 1)
  private var timeObserver: Any?

  // MARK: - Convenience Getters

  private var audioSession: AVAudioSession { Self.audioSession }
  private var notificationCenter: NotificationCenter {
    NotificationCenter.default
  }
  private init() {
    commandCenter = CommandCenter(accessKey)
  }

  // MARK: - Public Methods

  func start(_ podcastEpisode: PodcastEpisode) async throws {
    try await load(podcastEpisode)
    play()
  }

  func load(_ podcastEpisode: PodcastEpisode) async throws {
    guard let url = podcastEpisode.episode.media else {
      throw PlaybackError.noURL(podcastEpisode.episode)
    }
    await loadingSemaphor.wait()
    defer { loadingSemaphor.signal() }

    stopIntegrations()
    removeObservers()
    pause()
    status = .loading

    let avAsset = AVURLAsset(url: url)
    let (isPlayable, duration) = try await avAsset.load(.isPlayable, .duration)
    guard isPlayable else {
      Task { @MainActor in Alert.shared("Could not play podcast episode") }
      status = .paused
      addObservers()
      startIntegrations()
      throw PlaybackError.notPlayable(url)
    }

    do {
      try audioSession.setActive(true)
    } catch {
      Task { @MainActor in Alert.shared("Failed to set audio session active") }
      stop()
      throw PlaybackError.notActive
    }

    avPlayerItem = AVPlayerItem(asset: avAsset)
    avPlayer.replaceCurrentItem(with: avPlayerItem)

    await setPodcastEpisode(podcastEpisode)
    setDuration(duration)

    status = .active
    addObservers()
    startIntegrations()
  }

  func play() {
    guard status.playable else { return }
    avPlayer.play()
  }

  func pause() {
    avPlayer.pause()
  }

  func stop() {
    stopIntegrations()
    removeObservers()
    pause()
    setCurrentTime(CMTime.zero)
    nowPlayingInfo = nil
    status = .stopped

    do {
      try audioSession.setActive(false)
    } catch {
      Task { @MainActor in
        Alert.shared("Failed to set audio session as inactive")
      }
    }
  }

  func seekForward(_ duration: CMTime) {
    seek(to: avPlayer.currentTime() + duration)
  }

  func seekBackward(_ duration: CMTime) {
    seek(to: avPlayer.currentTime() - duration)
  }

  func seek(to time: CMTime) {
    removeTimeObserver()
    setCurrentTime(time)
    avPlayer.seek(to: time) { [unowned self] completed in
      if completed {
        Task { @PlayActor in addTimeObserver() }
      }
    }
  }

  // MARK: - Private State Management

  private func setPodcastEpisode(_ podcastEpisode: PodcastEpisode) async {
    guard let currentTime = podcastEpisode.episode.currentTime else {
      fatalError("Setting podcast episode with no time?")
    }

    nowPlayingInfo = await NowPlayingInfo(podcastEpisode, accessKey)
    Task { @MainActor in PlayState.shared.setOnDeck(podcastEpisode, accessKey) }
    Task(priority: .utility) {
      Persistence.currentEpisodeID.save(podcastEpisode.episode.id)
    }

    seek(to: currentTime)
  }

  private func setDuration(_ duration: CMTime) {
    guard var nowPlayingInfo = nowPlayingInfo else {
      fatalError("setting duration with no nowPlayingInfo?")
    }

    nowPlayingInfo.duration(duration)
    Task { @MainActor in PlayState.shared.setDuration(duration, accessKey) }
  }

  private func setCurrentTime(_ currentTime: CMTime) {
    guard var nowPlayingInfo = nowPlayingInfo else {
      fatalError("setting currentTime with no nowPlayingInfo?")
    }

    nowPlayingInfo.currentTime(currentTime)
    Task { @MainActor in
      PlayState.shared.setCurrentTime(currentTime, accessKey)
    }
  }

  // MARK: - Private Observers / Integrators

  private func resume() async throws {
    if let episodeID: Int64 = Persistence.currentEpisodeID.load(),
      let podcastEpisode = try await Repo.shared.db.read({ db in
        try Episode
          .filter(id: episodeID)
          .including(required: Episode.podcast)
          .asRequest(of: PodcastEpisode.self)
          .fetchOne(db)
      })
    {
      try await load(podcastEpisode)
    }
  }

  private func startIntegrations() {
    startCommandCenter()
    startInterruptionNotifications()
  }

  private func stopIntegrations() {
    stopCommandCenter()
    stopInterruptionNotifications()
  }

  private func startCommandCenter() {
    stopCommandCenter()
    commandCenter.start()
    self.commandObservingTask = Task { @PlayActor in
      for await command in commandCenter.commands() {
        if Task.isCancelled { break }
        switch command {
        case .play:
          play()
        case .pause:
          pause()
        case .togglePlayPause:
          if status.playing { pause() } else { play() }
        case .skipForward(let interval):
          seekForward(CMTime.inSeconds(interval))
        case .skipBackward(let interval):
          seekBackward(CMTime.inSeconds(interval))
        case .playbackPosition(let position):
          seek(to: CMTime.inSeconds(position))
        }
      }
    }
  }

  private func stopCommandCenter() {
    commandCenter.stop()
    if let commandObservingTask = self.commandObservingTask {
      commandObservingTask.cancel()
      self.commandObservingTask = nil
    }
  }

  private func startInterruptionNotifications() {
    stopInterruptionNotifications()
    self.interruptionObservingTask = Task { @PlayActor in
      for await notification in notificationCenter.notifications(
        named: AVAudioSession.interruptionNotification
      ) {
        if Task.isCancelled { break }
        switch AudioInterruption.parse(notification) {
        case .pause:
          pause()
        case .resume:
          play()
        case .ignore:
          break
        @unknown default:
          fatalError("Interruption Notification unknown?!")
        }
      }
    }
  }

  private func stopInterruptionNotifications() {
    if let interruptionObservingTask = self.interruptionObservingTask {
      interruptionObservingTask.cancel()
      self.interruptionObservingTask = nil
    }
  }

  private func addObservers() {
    addKVObservers()
    addTimeObserver()
  }

  private func removeObservers() {
    removeKVObservers()
    removeTimeObserver()
  }

  private func addKVObservers() {
    removeKVObservers()
    keyValueObservers.append(
      avPlayer.observe(
        \.timeControlStatus,
        options: .new,
        changeHandler: { [unowned self] playerItem, _ in
          switch playerItem.timeControlStatus {
          case AVPlayer.TimeControlStatus.paused:
            Task { @PlayActor in status = .paused }
          case AVPlayer.TimeControlStatus.playing:
            Task { @PlayActor in status = .playing }
          case AVPlayer.TimeControlStatus.waitingToPlayAtSpecifiedRate:
            Task { @PlayActor in status = .waiting }
          @unknown default:
            fatalError("Time control status unknown?")
          }
        }
      )
    )
  }

  private func removeKVObservers() {
    for keyValueObserver in keyValueObservers { keyValueObserver.invalidate() }
    keyValueObservers.removeAll(keepingCapacity: true)
  }

  private func addTimeObserver() {
    removeTimeObserver()
    timeObserver = avPlayer.addPeriodicTimeObserver(
      forInterval: CMTime.inSeconds(1),
      queue: .global(qos: .utility)
    ) { currentTime in
      Task { @PlayActor [unowned self] in setCurrentTime(currentTime) }
    }
  }

  private func removeTimeObserver() {
    if let timeObserver = timeObserver {
      avPlayer.removeTimeObserver(timeObserver)
      self.timeObserver = nil
    }
  }
}
