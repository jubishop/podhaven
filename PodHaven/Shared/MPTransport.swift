// Copyright Justin Bishop, 2024

import Foundation
import MediaPlayer

@globalActor
final actor MPActor {
  static let shared = MPActor()
}

@MPActor
final class MPTransport {
  static let shared = MPTransport()

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

  func onDeck(_ podcastEpisode: PodcastEpisode) {
    self.podcastEpisode = podcastEpisode
    var nowPlayingInfo: [String: Any] = [:]

    nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = podcast.title
    nowPlayingInfo[MPMediaItemPropertyMediaType] = NSNumber(
      value: MPMediaType.podcast.rawValue
    )
    if let episodeTitle = episode.title {
      nowPlayingInfo[MPMediaItemPropertyTitle] = episodeTitle
    }
    nowPlayingInfo[MPNowPlayingInfoCollectionIdentifier] =
      podcast.feedURL.absoluteString
    if let episodeURL = episode.media {
      nowPlayingInfo[MPNowPlayingInfoPropertyAssetURL] =
        episodeURL.absoluteString
    }
    nowPlayingInfo[MPNowPlayingInfoPropertyCurrentPlaybackDate] =
      episode.pubDate
    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(0)
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackProgress] = 0
    nowPlayingInfo[MPNowPlayingInfoPropertyExternalContentIdentifier] =
      episode.guid
    nowPlayingInfo[MPNowPlayingInfoPropertyExternalUserProfileIdentifier] =
      appIdentifier
    nowPlayingInfo[MPNowPlayingInfoPropertyIsLiveStream] = NSNumber(
      value: false
    )
    nowPlayingInfo[MPNowPlayingInfoPropertyMediaType] =
      NSNumber(value: MPNowPlayingInfoMediaType.audio.rawValue)
    nowPlayingInfo[MPNowPlayingInfoPropertyServiceIdentifier] = podcast.title
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackProgress] = Float(0.0)
    if let podcastLink = podcast.link {
      nowPlayingInfo[MPNowPlayingInfoPropertyServiceIdentifier] =
        podcastLink.absoluteString
    }

    infoCenter.nowPlayingInfo = nowPlayingInfo
    infoCenter.playbackState = .stopped
  }

  func duration(_ duration: CMTime) {
    guard infoCenter.nowPlayingInfo != nil else {
      fatalError("Setting duration on a nil nowPlayingInfo?")
    }
    infoCenter.nowPlayingInfo?[MPMediaItemPropertyPlaybackDuration] = NSNumber(
      value: CMTimeGetSeconds(duration)
    )
  }
}
