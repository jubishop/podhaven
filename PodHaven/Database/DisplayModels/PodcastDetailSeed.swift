// Copyright Justin Bishop, 2026

import Foundation
import IdentifiedCollections

struct PodcastDetailPresentation: Sendable {
  let podcast: DisplayedPodcast
  let episodes: IdentifiedArrayOf<ListedEpisode>
}

enum PodcastDetailSeed: Hashable, Sendable {
  case displayedPodcast(DisplayedPodcast)
  case listedPodcast(ListedPodcast)
  case unsavedPodcastSeries(UnsavedPodcastSeries)

  var initialPresentation: PodcastDetailPresentation {
    switch self {
    case .displayedPodcast(let podcast):
      return PodcastDetailPresentation(
        podcast: podcast,
        episodes: []
      )
    case .listedPodcast(let listedPodcast):
      return PodcastDetailPresentation(
        podcast: initialPodcast(from: listedPodcast),
        episodes: []
      )
    case .unsavedPodcastSeries(let unsavedPodcastSeries):
      return PodcastDetailPresentation(
        podcast: DisplayedPodcast(unsavedPodcastSeries.unsavedPodcast),
        episodes: IdentifiedArrayOf(
          uniqueElements: unsavedPodcastSeries.unsavedEpisodes.map {
            ListedEpisode(
              UnsavedPodcastEpisode(
                unsavedPodcast: unsavedPodcastSeries.unsavedPodcast,
                unsavedEpisode: $0
              )
            )
          }
        )
      )
    }
  }

  private func initialPodcast(from listedPodcast: ListedPodcast) -> DisplayedPodcast {
    if let unsavedPodcast = listedPodcast.unsavedSearchResult {
      return DisplayedPodcast(unsavedPodcast)
    }

    return DisplayedPodcast(PodcastDetailInitialPodcast(listedPodcast))
  }
}

// Internal because `DisplayedPodcast.Source.initialPresentation` names this
// type across files; init is fileprivate so the seed remains the only
// constructor.
struct PodcastDetailInitialPodcast:
  PodcastDisplayable,
  Searchable,
  Stringable,
  Hashable,
  Sendable
{
  let podcastID: Podcast.ID?
  let feedURL: FeedURL
  let iTunesID: ITunesPodcastID?
  let image: URL
  let title: String
  let description: String
  let link: URL?
  let subscriptionDate: Date?
  let defaultPlaybackRate: Double?
  let queueAllEpisodes: QueueAllEpisodes
  let cacheAllEpisodes: CacheAllEpisodes
  let notifyNewEpisodes: Bool
  let freshnessCadence: FreshnessCadence?

  var id: FeedURL { feedURL }
  var toString: String { "(\(feedURL.toString)) - \(title)" }
  var searchableString: String { "\(title) - \(description)" }

  fileprivate init(_ listedPodcast: ListedPodcast) {
    if let searchResult = listedPodcast.savedSearchResult {
      podcastID = searchResult.savedPodcast.id
      feedURL = searchResult.savedPodcast.feedURL
      iTunesID = searchResult.savedPodcast.iTunesID
      image = searchResult.savedPodcast.image
      title = searchResult.savedPodcast.title
      description = searchResult.originalPodcast.description
      link = searchResult.originalPodcast.link
      subscriptionDate = searchResult.savedPodcast.subscriptionDate
      defaultPlaybackRate = nil
      queueAllEpisodes = .never
      cacheAllEpisodes = .never
      notifyNewEpisodes = false
      freshnessCadence = nil
    } else if let listablePodcast = listedPodcast.listablePodcast {
      podcastID = listablePodcast.id
      feedURL = listablePodcast.feedURL
      iTunesID = listablePodcast.iTunesID
      image = listablePodcast.image
      title = listablePodcast.title
      description = ""
      link = nil
      subscriptionDate = listablePodcast.subscriptionDate
      defaultPlaybackRate = nil
      queueAllEpisodes = .never
      cacheAllEpisodes = .never
      notifyNewEpisodes = false
      freshnessCadence = nil
    } else {
      Assert.fatal("Cannot build PodcastDetailInitialPodcast from unsaved search result")
    }
  }
}
