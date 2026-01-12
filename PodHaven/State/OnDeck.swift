// Copyright Justin Bishop, 2026

import AVFoundation
import UIKit

@dynamicMemberLookup
struct OnDeck: EpisodeListable, Identifiable, Stringable {
  private let podcastEpisode: PodcastEpisode
  var artwork: UIImage?
  var currentTime: CMTime

  init(podcastEpisode: PodcastEpisode, artwork: UIImage? = nil, currentTime: CMTime? = nil) {
    self.podcastEpisode = podcastEpisode
    self.artwork = artwork
    self.currentTime = currentTime ?? podcastEpisode.currentTime
  }

  // MARK: - Dynamic Member Lookup

  subscript<T>(dynamicMember keyPath: KeyPath<PodcastEpisode, T>) -> T {
    podcastEpisode[keyPath: keyPath]
  }

  // MARK: - EpisodeListable

  var id: Episode.ID { podcastEpisode.id }
  var mediaGUID: MediaGUID { podcastEpisode.mediaGUID }
  var title: String { podcastEpisode.title }
  var pubDate: Date { podcastEpisode.pubDate }
  var duration: CMTime { podcastEpisode.duration }
  var queueOrder: Int? { podcastEpisode.queueOrder }
  var cacheStatus: Episode.CacheStatus { podcastEpisode.cacheStatus }
  var saveInCache: Bool { podcastEpisode.saveInCache }
  var finishDate: Date? { podcastEpisode.finishDate }
  var image: URL { podcastEpisode.image }

  // MARK: - Stringable

  var toString: String { podcastEpisode.toString }

  // MARK: - Hashable

  func hash(into hasher: inout Hasher) {
    hasher.combine(podcastEpisode)
  }

  // MARK: - Equatable

  static func == (lhs: OnDeck, rhs: OnDeck) -> Bool {
    lhs.podcastEpisode == rhs.podcastEpisode
  }
}
