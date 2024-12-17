// Copyright Justin Bishop, 2024

import Foundation
import MediaPlayer

final class NowPlayingInfo {
  // MARK: - Convenience Getters

  private let appIdentifier = "com.artisanal.podhaven"
  private let infoCenter = MPNowPlayingInfoCenter.default()
  private var podcastEpisode: PodcastEpisode?
  private var episode: Episode {
    guard let podcastEpisode = podcastEpisode else {
      fatalError("Calling episode when no podcastEpisode loaded?")
    }
    return podcastEpisode.episode
  }
  private var podcast: Podcast {
    guard let podcastEpisode = podcastEpisode else {
      fatalError("Calling podcast when no podcast loaded?")
    }
    return podcastEpisode.podcast
  }

  // MARK: - State Management

  var _status: PlayState.Status = .stopped
  var status: PlayState.Status {
    get { _status }
    set {
      guard newValue != _status else { return }
      _status = newValue
      infoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] =
        newValue == .playing ? 1.0 : 0.0
    }
  }
  init(_ key: PlayManagerAccessKey) {}

  // MARK: - Public Methods

  func onDeck(_ podcastEpisode: PodcastEpisode) {
    self.podcastEpisode = podcastEpisode

    var nowPlayingInfo: [String: Any] = [:]

    nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = podcast.title
    nowPlayingInfo[MPMediaItemPropertyMediaType] =
      MPMediaType.podcast.rawValue
    nowPlayingInfo[MPMediaItemPropertyTitle] = episode.title
    nowPlayingInfo[MPNowPlayingInfoCollectionIdentifier] =
      podcast.feedURL.absoluteString
    if let episodeURL = episode.media {
      nowPlayingInfo[MPNowPlayingInfoPropertyAssetURL] = episodeURL
    }
    nowPlayingInfo[MPNowPlayingInfoPropertyCurrentPlaybackDate] =
      episode.pubDate
    nowPlayingInfo[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(0)
    nowPlayingInfo[MPNowPlayingInfoPropertyExternalContentIdentifier] =
      episode.guid
    nowPlayingInfo[MPNowPlayingInfoPropertyExternalUserProfileIdentifier] =
      appIdentifier
    nowPlayingInfo[MPNowPlayingInfoPropertyIsLiveStream] = false
    nowPlayingInfo[MPNowPlayingInfoPropertyMediaType] =
      MPNowPlayingInfoMediaType.audio.rawValue
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackProgress] = Float(0.0)
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 0.0
    if let podcastLink = podcast.link {
      nowPlayingInfo[MPNowPlayingInfoPropertyServiceIdentifier] =
        podcastLink.absoluteString
    }

    infoCenter.nowPlayingInfo = nowPlayingInfo
  }

  func duration(_ duration: CMTime) {
    infoCenter.nowPlayingInfo?[MPMediaItemPropertyPlaybackDuration] = NSNumber(
      value: CMTimeGetSeconds(duration)
    )
  }
}
