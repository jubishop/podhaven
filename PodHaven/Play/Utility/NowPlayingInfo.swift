// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import MediaPlayer

struct NowPlayingInfo {
  private static let log = Log.as(LogSubsystem.Play.nowPlayingInfo)

  // MARK: - State Management

  private let onDeck: OnDeck

  // MARK: - Initializing

  init(_ onDeck: OnDeck) {
    Self.log.debug("nowPlayingInfo.init: onDeck: \(onDeck.toString)")
    self.onDeck = onDeck

    var nowPlayingInfo: [String: Any] = [:]

    nowPlayingInfo[MPMediaItemPropertyPodcastTitle] = onDeck.podcastTitle
    if let image = onDeck.image {
      nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(
        boundsSize: image.size,
        requestHandler: { size in image }
      )
    }
    nowPlayingInfo[MPMediaItemPropertyMediaType] = MPMediaType.podcast.rawValue
    nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = onDeck.duration.seconds
    nowPlayingInfo[MPMediaItemPropertyTitle] = onDeck.episodeTitle
    if let pubDate = onDeck.pubDate {
      nowPlayingInfo[MPMediaItemPropertyReleaseDate] = pubDate
    }
    nowPlayingInfo[MPNowPlayingInfoPropertyAssetURL] = onDeck.mediaURL
    nowPlayingInfo[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0.0
    nowPlayingInfo[MPNowPlayingInfoPropertyExternalContentIdentifier] = onDeck.guid.rawValue
    nowPlayingInfo[MPNowPlayingInfoPropertyIsLiveStream] = false
    nowPlayingInfo[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackProgress] = 0.0
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 0.0

    var infoCenter = Container.shared.mpNowPlayingInfoCenter()
    infoCenter.nowPlayingInfo = nowPlayingInfo
  }

  // MARK: - Modifying

  func clear() {
    Self.log.debug("clear: executing")
    var infoCenter = Container.shared.mpNowPlayingInfoCenter()
    infoCenter.nowPlayingInfo = nil
  }

  func setCurrentTime(_ currentTime: CMTime) {
    Self.log.trace("setCurrentTime: \(currentTime)")
    var infoCenter = Container.shared.mpNowPlayingInfoCenter()
    infoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] =
      currentTime.seconds
    infoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackProgress] =
      currentTime.seconds / onDeck.duration.seconds
  }

  func playing(_ playing: Bool) {
    Self.log.debug("playing: \(playing)")
    var infoCenter = Container.shared.mpNowPlayingInfoCenter()
    infoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] =
      playing ? 1.0 : 0.0
  }
}
