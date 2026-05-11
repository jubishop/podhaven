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
// `.loaded` is the fully-displayable episode (saved or unsaved). Both
// cases conform to `EpisodeDisplayable`, so a single existential helper
// forwards every property — unlike the podcast side, the bridge episode
// legitimately carries all `EpisodeDisplayable` fields with honest values.
enum EpisodeDetailContent:
  EpisodeDisplayable,
  Hashable,
  Sendable
{
  case initial(EpisodeDetailInitialEpisode)
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

// Snapshot of list-row episode data displayed before the detail view
// hydrates. Conforms to `EpisodeDisplayable` because the bridge legitimately
// carries every required field with honest values — `podcastTitle` /
// `queueDate` come straight from the list row, `description` is `nil` for
// the saved arm (genuinely unknown until hydration) and the unsaved
// episode's own description for the unsaved arm. Contrast with the podcast
// bridge, which can only honestly fulfill `PodcastListable` because the
// detail-only fields (`queueAllEpisodes`, etc.) have no list-row source.
//
// Internal because `EpisodeDetailContent.initial` names this type across
// files; init is fileprivate so `EpisodeDetailSeed` remains the only
// constructor.
struct EpisodeDetailInitialEpisode:
  EpisodeDisplayable,
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
