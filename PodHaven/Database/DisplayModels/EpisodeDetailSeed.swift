// Copyright Justin Bishop, 2026

import AVFoundation
import Foundation

enum EpisodeDetailSeed: Hashable, Sendable {
  case displayedEpisode(DisplayedEpisode)
  case listedEpisode(ListedEpisode)

  var initialEpisode: EpisodeDetailContent {
    switch self {
    case .displayedEpisode(let episode):
      return .loaded(episode)
    case .listedEpisode(let listedEpisode):
      return .initial(EpisodeDetailInitialEpisode(listedEpisode))
    }
  }
}

// Live state of `EpisodeDetailViewModel.episode`. `.initial` is the
// transient list-row snapshot displayed before the saved episode hydrates;
// `.loaded` is the fully-displayable episode (saved or unsaved).
enum EpisodeDetailContent:
  EpisodeListable,
  Hashable,
  Sendable
{
  case initial(EpisodeDetailInitialEpisode)
  case loaded(DisplayedEpisode)

  var loaded: DisplayedEpisode? {
    guard case .loaded(let episode) = self else { return nil }
    return episode
  }

  // MARK: - EpisodeListable + header surface

  var id: MediaGUID { mediaGUID }

  var episodeID: Episode.ID? {
    switch self {
    case .initial(let episode): return episode.episodeID
    case .loaded(let episode): return episode.episodeID
    }
  }

  var mediaGUID: MediaGUID {
    switch self {
    case .initial(let episode): return episode.mediaGUID
    case .loaded(let episode): return episode.mediaGUID
    }
  }

  var feedURL: FeedURL {
    switch self {
    case .initial(let episode): return episode.feedURL
    case .loaded(let episode): return episode.feedURL
    }
  }

  var title: String {
    switch self {
    case .initial(let episode): return episode.title
    case .loaded(let episode): return episode.title
    }
  }

  var pubDate: Date {
    switch self {
    case .initial(let episode): return episode.pubDate
    case .loaded(let episode): return episode.pubDate
    }
  }

  var duration: CMTime {
    switch self {
    case .initial(let episode): return episode.duration
    case .loaded(let episode): return episode.duration
    }
  }

  var currentTime: CMTime {
    switch self {
    case .initial(let episode): return episode.currentTime
    case .loaded(let episode): return episode.currentTime
    }
  }

  var queueOrder: Int? {
    switch self {
    case .initial(let episode): return episode.queueOrder
    case .loaded(let episode): return episode.queueOrder
    }
  }

  var cacheStatus: Episode.CacheStatus {
    switch self {
    case .initial(let episode): return episode.cacheStatus
    case .loaded(let episode): return episode.cacheStatus
    }
  }

  var saveInCache: Bool {
    switch self {
    case .initial(let episode): return episode.saveInCache
    case .loaded(let episode): return episode.saveInCache
    }
  }

  var finishDate: Date? {
    switch self {
    case .initial(let episode): return episode.finishDate
    case .loaded(let episode): return episode.finishDate
    }
  }

  var rating: EpisodeRating? {
    switch self {
    case .initial(let episode): return episode.rating
    case .loaded(let episode): return episode.rating
    }
  }

  var image: URL {
    switch self {
    case .initial(let episode): return episode.image
    case .loaded(let episode): return episode.image
    }
  }

  var podcastImage: URL {
    switch self {
    case .initial(let episode): return episode.podcastImage
    case .loaded(let episode): return episode.podcastImage
    }
  }

  var podcastTitle: String {
    switch self {
    case .initial(let episode): return episode.podcastTitle
    case .loaded(let episode): return episode.podcastTitle
    }
  }

  var description: String? {
    switch self {
    case .initial(let episode): return episode.description
    case .loaded(let episode): return episode.description
    }
  }

  var queueDate: Date? {
    switch self {
    case .initial(let episode): return episode.queueDate
    case .loaded(let episode): return episode.queueDate
    }
  }

  var isSaved: Bool { episodeID != nil }
  var queued: Bool { queueOrder != nil }
  var finished: Bool { finishDate != nil }

  var toString: String {
    switch self {
    case .initial(let episode): return episode.toString
    case .loaded(let episode): return episode.toString
    }
  }
}

// Snapshot of list-row episode data displayed before the detail view
// hydrates. Carries only what the list row knows: episode-listable fields
// plus the displayable extras (`podcastTitle`, `description`, `queueDate`)
// that are present in both source variants. Does **not** claim
// `EpisodeDisplayable` conformance — the wrapper-level `Displayed*`
// surface is reserved for fully-loaded data.
//
// Internal because `EpisodeDetailContent.initial` names this type across
// files; init is fileprivate so `EpisodeDetailSeed` remains the only
// constructor.
struct EpisodeDetailInitialEpisode:
  EpisodeListable,
  Sendable
{
  let episodeID: Episode.ID?
  let mediaGUID: MediaGUID
  let feedURL: FeedURL
  let title: String
  let podcastTitle: String
  let pubDate: Date
  let description: String?
  let duration: CMTime
  let currentTime: CMTime
  let queueDate: Date?
  let queueOrder: Int?
  let cacheStatus: Episode.CacheStatus
  let finishDate: Date?
  let image: URL
  let podcastImage: URL
  let saveInCache: Bool
  let rating: EpisodeRating?

  var id: MediaGUID { mediaGUID }

  fileprivate init(_ listedEpisode: ListedEpisode) {
    switch listedEpisode.source {
    case .unsaved(let unsavedPodcastEpisode):
      episodeID = unsavedPodcastEpisode.episodeID
      mediaGUID = unsavedPodcastEpisode.mediaGUID
      feedURL = unsavedPodcastEpisode.feedURL
      title = unsavedPodcastEpisode.title
      podcastTitle = unsavedPodcastEpisode.podcastTitle
      pubDate = unsavedPodcastEpisode.pubDate
      description = unsavedPodcastEpisode.description
      duration = unsavedPodcastEpisode.duration
      currentTime = unsavedPodcastEpisode.currentTime
      queueDate = unsavedPodcastEpisode.queueDate
      queueOrder = unsavedPodcastEpisode.queueOrder
      cacheStatus = unsavedPodcastEpisode.cacheStatus
      finishDate = unsavedPodcastEpisode.finishDate
      image = unsavedPodcastEpisode.image
      podcastImage = unsavedPodcastEpisode.podcastImage
      saveInCache = unsavedPodcastEpisode.saveInCache
      rating = unsavedPodcastEpisode.rating
    case .saved(let listablePodcastEpisode):
      episodeID = listablePodcastEpisode.id
      mediaGUID = listablePodcastEpisode.mediaGUID
      feedURL = listablePodcastEpisode.feedURL
      title = listablePodcastEpisode.title
      podcastTitle = listablePodcastEpisode.podcastTitle
      pubDate = listablePodcastEpisode.pubDate
      description = nil
      duration = listablePodcastEpisode.duration
      currentTime = listablePodcastEpisode.currentTime
      queueDate = listablePodcastEpisode.queueDate
      queueOrder = listablePodcastEpisode.queueOrder
      cacheStatus = listablePodcastEpisode.cacheStatus
      finishDate = listablePodcastEpisode.finishDate
      image = listablePodcastEpisode.image
      podcastImage = listablePodcastEpisode.podcastImage
      saveInCache = listablePodcastEpisode.saveInCache
      rating = listablePodcastEpisode.rating
    }
  }
}
