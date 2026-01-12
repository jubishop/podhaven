// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import Logging
import MediaPlayer
import Sharing
import Tagged

enum NowPlayingInfo {
  private static let log = Log.as(LogSubsystem.Play.nowPlayingInfo)

  // MARK: - Initializing

  /// Sets up NowPlayingInfo.
  static func setOnDeck(_ onDeck: PodcastEpisode) {
    Self.log.debug("setOnDeck: \(onDeck.toString)")

    var nowPlayingInfo: [String: Any] = [:]

    nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = onDeck.podcastTitle
    nowPlayingInfo[MPMediaItemPropertyArtist] = onDeck.podcastTitle
    nowPlayingInfo[MPMediaItemPropertyPodcastTitle] = onDeck.podcastTitle
    nowPlayingInfo[MPMediaItemPropertyMediaType] = MPMediaType.podcast.rawValue
    nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = onDeck.duration.safe.seconds
    nowPlayingInfo[MPMediaItemPropertyTitle] = onDeck.title
    nowPlayingInfo[MPMediaItemPropertyReleaseDate] = onDeck.pubDate
    nowPlayingInfo[MPNowPlayingInfoPropertyAssetURL] = onDeck.episode.mediaURL.rawValue
    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0.0
    nowPlayingInfo[MPNowPlayingInfoPropertyExternalContentIdentifier] = onDeck.episode.guid.rawValue
    nowPlayingInfo[MPNowPlayingInfoPropertyIsLiveStream] = false
    nowPlayingInfo[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackProgress] = 0.0
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 0.0

    var infoCenter = Container.shared.mpNowPlayingInfoCenter()
    infoCenter.nowPlayingInfo = nowPlayingInfo

    updateQueueCount()
    updateDefaultPlaybackRate(for: onDeck)
  }

  // MARK: - Modifying

  static func clear() {
    Self.log.debug("clear: executing")

    var infoCenter = Container.shared.mpNowPlayingInfoCenter()
    infoCenter.nowPlayingInfo = nil
  }

  static func setImage(_ image: UIImage?) {
    Self.log.debug("setImage")

    var infoCenter = Container.shared.mpNowPlayingInfoCenter()
    guard var nowPlayingInfo = infoCenter.nowPlayingInfo else {
      Self.log.warning("NowPlayingInfo is nil in setImage?")
      return
    }
    defer { infoCenter.nowPlayingInfo = nowPlayingInfo }

    if let image {
      nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(
        boundsSize: image.size,
        requestHandler: { size in image }
      )
    } else {
      nowPlayingInfo[MPMediaItemPropertyArtwork] = nil
    }
  }

  static func setCurrentTime(_ currentTime: CMTime) {
    Self.log.trace("setCurrentTime: \(currentTime)")

    guard let duration = Container.shared.sharedState().onDeck?.duration else { return }

    var infoCenter = Container.shared.mpNowPlayingInfoCenter()
    guard var nowPlayingInfo = infoCenter.nowPlayingInfo else { return }
    defer { infoCenter.nowPlayingInfo = nowPlayingInfo }

    let elapsedSeconds = currentTime.safe.seconds
    let durationSeconds = duration.safe.seconds

    guard elapsedSeconds >= 0 else {
      Self.log.warning("elapsedSeconds is less than 0, not updating elapsedTime")
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

    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] =
      elapsedSeconds.clamped(to: 0.0...durationSeconds)
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackProgress] =
      (elapsedSeconds / durationSeconds).clamped(to: 0.0...1.0)
  }

  static func setPlaybackRate(_ rate: Float) {
    Self.log.debug("setPlaybackRate: \(rate)")

    var infoCenter = Container.shared.mpNowPlayingInfoCenter()
    guard var nowPlayingInfo = infoCenter.nowPlayingInfo else { return }
    defer { infoCenter.nowPlayingInfo = nowPlayingInfo }

    guard rate.isFinite
    else {
      Self.log.warning("Not updating playBackRate, as it is not finite?")
      nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = nil
      return
    }

    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = Double(rate.clamped(to: -1.0...2.0))
  }

  static func updateQueueCount() {
    Self.log.debug("updateQueueCount")

    var infoCenter = Container.shared.mpNowPlayingInfoCenter()
    guard var nowPlayingInfo = infoCenter.nowPlayingInfo else { return }
    defer { infoCenter.nowPlayingInfo = nowPlayingInfo }

    switch Container.shared.userSettings().nextTrackBehavior {
    case .nextEpisode:
      nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueIndex] = 0
      nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueCount] =
        Container.shared.sharedState().queueCount + 1
    case .skipInterval:
      nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueIndex] = nil
      nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueCount] = nil
    }
  }

  static func updateDefaultPlaybackRate(for podcastEpisode: PodcastEpisode? = nil) {
    Self.log.debug("updateDefaultPlaybackRate")

    let podcast = podcastEpisode?.podcast ?? Container.shared.sharedState().onDeck?.podcast
    let defaultPlaybackRate =
      podcast?.defaultPlaybackRate ?? Container.shared.userSettings().defaultPlaybackRate

    var infoCenter = Container.shared.mpNowPlayingInfoCenter()
    guard var nowPlayingInfo = infoCenter.nowPlayingInfo else { return }
    defer { infoCenter.nowPlayingInfo = nowPlayingInfo }

    nowPlayingInfo[MPNowPlayingInfoPropertyDefaultPlaybackRate] = defaultPlaybackRate
  }
}
