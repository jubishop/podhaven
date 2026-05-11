// Copyright Justin Bishop, 2026

import AVFoundation
import Foundation

// View-facing projection of `EpisodeDetailViewModel.state`. `.initial` is the
// transient list-row snapshot displayed before the saved episode hydrates;
// `.loaded` is the fully-displayable episode (saved or unsaved). Both arms
// conform to `EpisodeDisplayable`, so a single existential helper forwards
// every property.
enum EpisodeDetailContent:
  EpisodeDisplayable,
  Hashable,
  Sendable
{
  case initial(ListedEpisode)
  case loaded(DisplayedEpisode)

  var loaded: DisplayedEpisode? {
    guard case .loaded(let episode) = self else { return nil }
    return episode
  }

  private var canonicalEpisode: any EpisodeDisplayable {
    switch self {
    case .initial(let episode): return episode
    case .loaded(let episode): return episode
    }
  }

  // MARK: - EpisodeListable / EpisodeFoundational

  var id: MediaGUID { mediaGUID }
  var episodeID: Episode.ID? { canonicalEpisode.episodeID }
  var mediaGUID: MediaGUID { canonicalEpisode.mediaGUID }
  var feedURL: FeedURL { canonicalEpisode.feedURL }
  var title: String { canonicalEpisode.title }
  var pubDate: Date { canonicalEpisode.pubDate }
  var duration: CMTime { canonicalEpisode.duration }
  var currentTime: CMTime { canonicalEpisode.currentTime }
  var queueOrder: Int? { canonicalEpisode.queueOrder }
  var cacheStatus: Episode.CacheStatus { canonicalEpisode.cacheStatus }
  var saveInCache: Bool { canonicalEpisode.saveInCache }
  var finishDate: Date? { canonicalEpisode.finishDate }
  var rating: EpisodeRating? { canonicalEpisode.rating }
  var image: URL { canonicalEpisode.image }
  var podcastImage: URL { canonicalEpisode.podcastImage }
  var toString: String { canonicalEpisode.toString }

  // MARK: - EpisodeDisplayable

  var podcastTitle: String { canonicalEpisode.podcastTitle }
  var description: String? { canonicalEpisode.description }
  var queueDate: Date? { canonicalEpisode.queueDate }
}
