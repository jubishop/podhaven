// Copyright Justin Bishop, 2024

import Foundation
import MediaPlayer

struct NowPlayingInfo: Sendable {
  // MARK: - State Management

  let podcastEpisode: PodcastEpisode
  private var currentTime: CMTime?
  private var duration: CMTime?
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

  // MARK: - Convenience Getters

  private let appIdentifier = "com.artisanal.podhaven"
  private var infoCenter: MPNowPlayingInfoCenter {
    MPNowPlayingInfoCenter.default()
  }
  private var episode: Episode { podcastEpisode.episode }
  private var podcast: Podcast { podcastEpisode.podcast }

  // MARK: - Initializing

  init(_ podcastEpisode: PodcastEpisode, _ key: PlayManagerAccessKey) async {
    self.podcastEpisode = podcastEpisode

    var nowPlayingInfo: [String: Any] = [:]

    nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = podcast.title
    if let imageURL = podcast.image,
      let image = try? await Images.shared.fetchImage(imageURL)
    {
      nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(
        boundsSize: image.size,
        requestHandler: { size in image }
      )
    }
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

  mutating func duration(_ duration: CMTime) {
    self.duration = duration
    infoCenter.nowPlayingInfo?[MPMediaItemPropertyPlaybackDuration] =
      NSNumber(value: CMTimeGetSeconds(duration))
    updateProgress()
  }

  mutating func currentTime(_ currentTime: CMTime) {
    self.currentTime = currentTime
    infoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] =
      NSNumber(value: CMTimeGetSeconds(currentTime))
    updateProgress()

    var episode = podcastEpisode.episode
    Task(priority: .utility) {
      episode.currentTime = currentTime
      try await Repo.shared.update(episode)
    }
  }

  // MARK: - Private Methods

  private func updateProgress() {
    guard let duration = self.duration, let currentTime = self.currentTime
    else { return }
    infoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackProgress] =
      CMTimeGetSeconds(currentTime) / CMTimeGetSeconds(duration)
  }
}
