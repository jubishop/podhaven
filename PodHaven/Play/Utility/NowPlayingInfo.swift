// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import MediaPlayer

struct NowPlayingInfo {
  // MARK: - State Management

  private let onDeck: OnDeck

  // MARK: - Convenience Getters

  private let appIdentifier = "com.artisanal.podhaven"

  // MARK: - Initializing

  init(_ onDeck: OnDeck) {
    self.onDeck = onDeck

    var nowPlayingInfo: [String: Any] = [:]

    nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = onDeck.podcastTitle
    if let image = onDeck.image {
      nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(
        boundsSize: image.size,
        requestHandler: { size in image }
      )
    }
    nowPlayingInfo[MPMediaItemPropertyMediaType] = MPMediaType.podcast.rawValue
    nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = NSNumber(
      value: CMTimeGetSeconds(onDeck.duration)
    )
    nowPlayingInfo[MPMediaItemPropertyTitle] = onDeck.episodeTitle
    nowPlayingInfo[MPNowPlayingInfoCollectionIdentifier] = onDeck.feedURL.rawValue
    nowPlayingInfo[MPNowPlayingInfoPropertyAssetURL] = onDeck.media.rawValue
    nowPlayingInfo[MPNowPlayingInfoPropertyCurrentPlaybackDate] = onDeck.pubDate
    nowPlayingInfo[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(0)
    nowPlayingInfo[MPNowPlayingInfoPropertyExternalContentIdentifier] =
      onDeck.guid.rawValue
    nowPlayingInfo[MPNowPlayingInfoPropertyExternalUserProfileIdentifier] =
      appIdentifier
    nowPlayingInfo[MPNowPlayingInfoPropertyIsLiveStream] = false
    nowPlayingInfo[MPNowPlayingInfoPropertyMediaType] =
      MPNowPlayingInfoMediaType.audio.rawValue
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackProgress] = Float(0.0)
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 0.0
    if let podcastURL = onDeck.podcastURL {
      nowPlayingInfo[MPNowPlayingInfoPropertyServiceIdentifier] =
        podcastURL.absoluteString
    }

    var infoCenter = Container.shared.mpNowPlayingInfoCenter()
    infoCenter.nowPlayingInfo = nowPlayingInfo
  }

  func clear() {
    var infoCenter = Container.shared.mpNowPlayingInfoCenter()
    infoCenter.nowPlayingInfo = nil
  }

  func setCurrentTime(_ currentTime: CMTime) {
    var infoCenter = Container.shared.mpNowPlayingInfoCenter()
    infoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] =
      NSNumber(value: CMTimeGetSeconds(currentTime))
    infoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackProgress] =
      CMTimeGetSeconds(currentTime) / CMTimeGetSeconds(onDeck.duration)
  }

  func playing(_ playing: Bool) {
    var infoCenter = Container.shared.mpNowPlayingInfoCenter()
    infoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] =
      playing ? 1.0 : 0.0
  }
}
