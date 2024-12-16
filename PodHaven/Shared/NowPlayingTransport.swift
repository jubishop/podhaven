// Copyright Justin Bishop, 2024

import Foundation
import MediaPlayer

@globalActor
final actor NowPlayingActor { static let shared = NowPlayingActor() }

@NowPlayingActor
final class NowPlayingTransport {
  // MARK: - Static Methods

  static let shared = NowPlayingTransport()

  static func configureNowPlayingInfoCenter() async {
    MPNowPlayingInfoCenter.default().playbackState = .stopped
  }

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

  private var _isLoading = false
  var isLoading: Bool {
    get { _isLoading }
    set {
      _isLoading = newValue
      updatePlaybackState()
    }
  }
  private var _isPlaying = false
  var isPlaying: Bool {
    get { _isPlaying }
    set {
      _isPlaying = newValue
      updatePlaybackState()
    }
  }
  private var _isActive = false
  var isActive: Bool {
    get { _isActive }
    set {
      _isActive = newValue
      updatePlaybackState()
    }
  }

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
    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(0)
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackProgress] = 0
    nowPlayingInfo[MPNowPlayingInfoPropertyExternalContentIdentifier] =
      episode.guid
    nowPlayingInfo[MPNowPlayingInfoPropertyExternalUserProfileIdentifier] =
      appIdentifier
    nowPlayingInfo[MPNowPlayingInfoPropertyIsLiveStream] = false
    nowPlayingInfo[MPNowPlayingInfoPropertyMediaType] =
      MPNowPlayingInfoMediaType.audio.rawValue
    nowPlayingInfo[MPNowPlayingInfoPropertyServiceIdentifier] = podcast.title
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackProgress] = Float(0.0)
    nowPlayingInfo[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
    if let podcastLink = podcast.link {
      nowPlayingInfo[MPNowPlayingInfoPropertyServiceIdentifier] =
        podcastLink.absoluteString
    }

    infoCenter.nowPlayingInfo = nowPlayingInfo
  }

  func duration(_ duration: CMTime) {
    guard infoCenter.nowPlayingInfo != nil else {
      fatalError("Setting duration on a nil nowPlayingInfo?")
    }

    infoCenter.nowPlayingInfo?[MPMediaItemPropertyPlaybackDuration] = NSNumber(
      value: CMTimeGetSeconds(duration)
    )
  }

  // MARK: - Private Methods

  private func updatePlaybackState() {
    guard !isLoading, isActive else {
      infoCenter.playbackState = .stopped
      return
    }

    infoCenter.playbackState = isPlaying ? .playing : .paused
  }
}
