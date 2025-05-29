// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import MediaPlayer

extension Container {
  var nowPlayingInfo: ParameterFactory<OnDeck, NowPlayingInfo> {
    ParameterFactory(self) { NowPlayingInfo($0) }.scope(.shared)
  }
}

struct NowPlayingInfo {
  // MARK: - State Management

  private let onDeck: OnDeck

  // MARK: - Convenience Getters

  private let appIdentifier = "com.artisanal.podhaven"
  private var infoCenter: MPNowPlayingInfoCenter { MPNowPlayingInfoCenter.default() }

  // MARK: - Initializing

  fileprivate init(_ onDeck: OnDeck) {
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

    infoCenter.nowPlayingInfo = nowPlayingInfo
  }

  func clear() {
    infoCenter.nowPlayingInfo = nil
  }

  func currentTime(_ currentTime: CMTime) {
    infoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] =
      NSNumber(value: CMTimeGetSeconds(currentTime))
    infoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackProgress] =
      CMTimeGetSeconds(currentTime) / CMTimeGetSeconds(onDeck.duration)
  }

  func playing(_ playing: Bool) {
    infoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] =
      playing ? 1.0 : 0.0
  }
}
