// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import Logging
import MediaPlayer
import Tagged

enum NowPlayingInfo {
  private static let log = Log.as(LogSubsystem.Play.nowPlayingInfo)

  // MARK: - Initializing

  // Sets up NowPlayingInfo.
  static func setOnDeck(_ onDeck: PodcastEpisode) {
    Self.log.debug("setOnDeck: \(onDeck.toString)")

    var nowPlayingInfo: [String: Any] = [:]
    let durationSeconds = onDeck.duration.safe.seconds
    let elapsedSeconds = onDeck.episode.currentTime.safe.seconds

    nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = onDeck.podcastTitle
    nowPlayingInfo[MPMediaItemPropertyArtist] = onDeck.podcastTitle
    nowPlayingInfo[MPMediaItemPropertyPodcastTitle] = onDeck.podcastTitle
    nowPlayingInfo[MPMediaItemPropertyMediaType] = MPMediaType.podcast.rawValue
    nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = durationSeconds
    nowPlayingInfo[MPMediaItemPropertyTitle] = onDeck.title
    nowPlayingInfo[MPMediaItemPropertyReleaseDate] = onDeck.pubDate
    nowPlayingInfo[MPNowPlayingInfoPropertyAssetURL] = onDeck.episode.mediaURL.rawValue
    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsedSeconds
    nowPlayingInfo[MPNowPlayingInfoPropertyExternalContentIdentifier] = onDeck.episode.guid.rawValue
    nowPlayingInfo[MPNowPlayingInfoPropertyIsLiveStream] = false
    nowPlayingInfo[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackProgress] =
      durationSeconds > 0 ? elapsedSeconds / durationSeconds : 0.0
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 0.0

    var infoCenter = Container.shared.mpNowPlayingInfoCenter()
    infoCenter.nowPlayingInfo = nowPlayingInfo
    infoCenter.playbackState = .paused

    updateQueueCount()
    updateDefaultPlaybackRate(for: onDeck)
  }

  // MARK: - Modifying

  static func clear() {
    Self.log.debug("clear: executing")

    var infoCenter = Container.shared.mpNowPlayingInfoCenter()
    infoCenter.nowPlayingInfo = nil
    infoCenter.playbackState = .stopped
  }

  static func setImage(_ image: UIImage?) {
    var infoCenter = Container.shared.mpNowPlayingInfoCenter()
    guard var nowPlayingInfo = infoCenter.nowPlayingInfo else {
      Self.log.debug("setImage: nowPlayingInfo is nil")
      return
    }
    defer { infoCenter.nowPlayingInfo = nowPlayingInfo }

    if let image {
      Self.log.debug("setImage: \(image.size)")
      nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(
        boundsSize: image.size,
        requestHandler: { size in image }
      )
    } else {
      Self.log.debug("setImage: nil")
      nowPlayingInfo[MPMediaItemPropertyArtwork] = nil
    }
  }

  static func setCurrentTime(_ currentTime: CMTime) {
    guard let duration = Container.shared.sharedState().onDeck?.duration else { return }

    var infoCenter = Container.shared.mpNowPlayingInfoCenter()
    guard var nowPlayingInfo = infoCenter.nowPlayingInfo else {
      Self.log.debug("setCurrentTime: nowPlayingInfo is nil")
      return
    }
    defer { infoCenter.nowPlayingInfo = nowPlayingInfo }

    let elapsedSeconds = currentTime.safe.seconds
    let durationSeconds = duration.safe.seconds

    guard elapsedSeconds >= 0 else {
      Self.log.warning(
        "elapsedSeconds is less than 0 (\(elapsedSeconds)), not updating elapsedTime"
      )
      nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = nil
      nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackProgress] = nil
      return
    }

    guard durationSeconds > 0 else {
      Self.log.info("durationSeconds is not greater than 0, not updating currentTime")
      nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsedSeconds
      nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackProgress] = nil
      return
    }

    Self.log.debug("setCurrentTime: \(currentTime)")
    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] =
      elapsedSeconds.clamped(to: 0.0...durationSeconds)
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackProgress] =
      (elapsedSeconds / durationSeconds).clamped(to: 0.0...1.0)
  }

  static func setPlaybackRate(_ rate: Float) {
    let currentTime = Container.shared.sharedState().onDeck?.currentTime ?? .zero

    // Log what iOS has before we overwrite — if a future stale-scrub recurs,
    // comparing previousElapsed to currentTime shows whether the dict was already stale.
    let infoCenter = Container.shared.mpNowPlayingInfoCenter()
    let previousElapsed =
      infoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double
    let previousElapsedString: String
    if let previousElapsed {
      previousElapsedString = String(describing: CMTime.seconds(previousElapsed))
    } else {
      previousElapsedString = "nil"
    }
    Self.log.debug(
      """
      setPlaybackRate: \(rate)
        currentTime: \(currentTime)
        previousElapsed: \(previousElapsedString)
      """
    )

    // iOS extrapolates the lock screen position as:
    //   displayedPosition = ElapsedPlaybackTime + PlaybackRate × (now - lastDictWrite)
    // Every rate transition (play/pause/speed change) must write BOTH the current
    // ElapsedPlaybackTime and the new PlaybackRate, so the extrapolation restarts
    // from the correct position. Without this, iOS extrapolates from whatever stale
    // ElapsedPlaybackTime was already in the dict.
    setCurrentTime(currentTime)

    var infoCenterVar = Container.shared.mpNowPlayingInfoCenter()
    guard var nowPlayingInfo = infoCenterVar.nowPlayingInfo else {
      Self.log.debug("setPlaybackRate: nowPlayingInfo is nil")
      return
    }
    defer { infoCenterVar.nowPlayingInfo = nowPlayingInfo }

    guard rate.isFinite else {
      Self.log.warning("Not updating playBackRate, as it is not finite?")
      nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = nil
      return
    }

    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = Double(rate.clamped(to: -1.0...2.0))
    // Mirror rate into the separate `playbackState` enum. Apple's NowPlayable
    // reference sample sets both; iOS may use the enum as a secondary signal
    // for lock-screen/CarPlay UI and for system-generated remote events.
    infoCenterVar.playbackState = rate > 0 ? .playing : .paused
  }

  static func updateQueueCount() {
    var infoCenter = Container.shared.mpNowPlayingInfoCenter()
    guard var nowPlayingInfo = infoCenter.nowPlayingInfo else {
      Self.log.debug("updateQueueCount: nowPlayingInfo is nil")
      return
    }
    defer { infoCenter.nowPlayingInfo = nowPlayingInfo }

    switch Container.shared.userSettings().nextTrackBehavior {
    case .nextEpisode:
      let queueCount = Container.shared.sharedState().queueCount
      Self.log.debug("updateQueueCount: nextEpisode, queueCount: \(queueCount)")
      nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueIndex] = 0
      nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueCount] = queueCount + 1
    case .skipInterval, .nextChapter:
      Self.log.debug("updateQueueCount: clearing (skipInterval/nextChapter)")
      nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueIndex] = nil
      nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueCount] = nil
    }
  }

  static func updateDefaultPlaybackRate(for podcastEpisode: PodcastEpisode? = nil) {
    let defaultPlaybackRate =
      podcastEpisode?.podcast.defaultPlaybackRate
      ?? Container.shared.sharedState().onDeck?.defaultPlaybackRate
      ?? Container.shared.userSettings().defaultPlaybackRate
    Self.log.debug("updateDefaultPlaybackRate: \(defaultPlaybackRate)")

    var infoCenter = Container.shared.mpNowPlayingInfoCenter()
    guard var nowPlayingInfo = infoCenter.nowPlayingInfo else {
      Self.log.debug("updateDefaultPlaybackRate: nowPlayingInfo is nil")
      return
    }
    defer { infoCenter.nowPlayingInfo = nowPlayingInfo }

    nowPlayingInfo[MPNowPlayingInfoPropertyDefaultPlaybackRate] = defaultPlaybackRate
  }
}
