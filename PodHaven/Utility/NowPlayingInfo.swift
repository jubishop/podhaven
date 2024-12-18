// Copyright Justin Bishop, 2024

import Foundation
import MediaPlayer

struct NowPlayingInfo: Sendable {
  // MARK: - Convenience Getters

  private let appIdentifier = "com.artisanal.podhaven"
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
  private var currentTime: CMTime?
  private var duration: CMTime?

  // MARK: - State Management

  var _status: PlayState.Status = .stopped
  var status: PlayState.Status {
    get { _status }
    set {
      guard newValue != _status else { return }
      _status = newValue
      MPNowPlayingInfoCenter.default().nowPlayingInfo?[
        MPNowPlayingInfoPropertyPlaybackRate
      ] = newValue == .playing ? 1.0 : 0.0
    }
  }
  init(_ key: PlayManagerAccessKey) {}

  // MARK: - Public Methods

  mutating func onDeck(_ podcastEpisode: PodcastEpisode) {
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

    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    addItemArtwork()
  }

  mutating func duration(_ duration: CMTime) {
    self.duration = duration
    MPNowPlayingInfoCenter.default().nowPlayingInfo?[
      MPMediaItemPropertyPlaybackDuration
    ] = NSNumber(value: CMTimeGetSeconds(duration))
    updateProgress()
  }

  mutating func currentTime(_ currentTime: CMTime) {
    self.currentTime = currentTime
    MPNowPlayingInfoCenter.default().nowPlayingInfo?[
      MPNowPlayingInfoPropertyElapsedPlaybackTime
    ] = NSNumber(value: CMTimeGetSeconds(currentTime))
    updateProgress()
  }

  // MARK: - Private Methods

  private func updateProgress() {
    guard let duration = self.duration, let currentTime = self.currentTime
    else { return }
    MPNowPlayingInfoCenter.default().nowPlayingInfo?[
      MPNowPlayingInfoPropertyPlaybackProgress
    ] = CMTimeGetSeconds(currentTime) / CMTimeGetSeconds(duration)
  }

  private func addItemArtwork() {
    if let imageURL = podcast.image {
      Task {
        if let (data, resp) = try? await URLSession.shared.data(from: imageURL),
           let httpResp = resp as? HTTPURLResponse,
           (200...299).contains(httpResp.statusCode),
           let uiImage = UIImage(data: data)
        {
          var nowPlayingInfo =
          MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [String: Any]()
          nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(
            boundsSize: uiImage.size
          ) {
            size in uiImage
          }
          MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        }
      }
    }
  }
}
