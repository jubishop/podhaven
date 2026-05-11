// Copyright Justin Bishop, 2026

import Foundation
import IdentifiedCollections

struct PodcastDetailPresentation: Sendable {
  let podcast: PodcastDetailContent
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
        podcast: .loaded(podcast),
        episodes: []
      )
    case .listedPodcast(let listedPodcast):
      return PodcastDetailPresentation(
        podcast: initialPodcast(from: listedPodcast),
        episodes: []
      )
    case .unsavedPodcastSeries(let unsavedPodcastSeries):
      return PodcastDetailPresentation(
        podcast: .loaded(DisplayedPodcast(unsavedPodcastSeries.unsavedPodcast)),
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

  private func initialPodcast(from listedPodcast: ListedPodcast) -> PodcastDetailContent {
    switch listedPodcast.source {
    case .unsavedSearchResult(let unsavedPodcast):
      return .loaded(DisplayedPodcast(unsavedPodcast))
    case .savedSearchResult(let result):
      return .initial(PodcastDetailInitialPodcast(savedSearchResult: result))
    case .saved(let listablePodcast):
      return .initial(PodcastDetailInitialPodcast(listablePodcast: listablePodcast))
    }
  }
}

// Live state of `PodcastDetailViewModel.podcast`. `.initial` is the
// transient list-row snapshot displayed before the saved series hydrates;
// `.loaded` is the fully-displayable podcast (saved or unsaved). Settings-
// only fields (defaultPlaybackRate, queueAllEpisodes, etc.) are accessible
// only via the `.loaded` case — the bridge type doesn't claim to have them.
enum PodcastDetailContent: Hashable, Sendable {
  case initial(PodcastDetailInitialPodcast)
  case loaded(DisplayedPodcast)

  var loaded: DisplayedPodcast? {
    guard case .loaded(let podcast) = self else { return nil }
    return podcast
  }

  // MARK: - PodcastListable + header surface

  var id: FeedURL { feedURL }

  var podcastID: Podcast.ID? {
    switch self {
    case .initial(let podcast): return podcast.podcastID
    case .loaded(let podcast): return podcast.podcastID
    }
  }

  var feedURL: FeedURL {
    switch self {
    case .initial(let podcast): return podcast.feedURL
    case .loaded(let podcast): return podcast.feedURL
    }
  }

  var iTunesID: ITunesPodcastID? {
    switch self {
    case .initial(let podcast): return podcast.iTunesID
    case .loaded(let podcast): return podcast.iTunesID
    }
  }

  var image: URL {
    switch self {
    case .initial(let podcast): return podcast.image
    case .loaded(let podcast): return podcast.image
    }
  }

  var title: String {
    switch self {
    case .initial(let podcast): return podcast.title
    case .loaded(let podcast): return podcast.title
    }
  }

  var subscriptionDate: Date? {
    switch self {
    case .initial(let podcast): return podcast.subscriptionDate
    case .loaded(let podcast): return podcast.subscriptionDate
    }
  }

  var subscribed: Bool { subscriptionDate != nil }
  var isSaved: Bool { podcastID != nil }

  var description: String {
    switch self {
    case .initial(let podcast): return podcast.description
    case .loaded(let podcast): return podcast.description
    }
  }

  var link: URL? {
    switch self {
    case .initial(let podcast): return podcast.link
    case .loaded(let podcast): return podcast.link
    }
  }

  var toString: String {
    switch self {
    case .initial(let podcast): return podcast.toString
    case .loaded(let podcast): return podcast.toString
    }
  }
}

// Snapshot of list-row data displayed before the detail view hydrates.
// Conforms to `PodcastListable` only — the detail-only fields it doesn't
// know yet (defaultPlaybackRate, queueAllEpisodes, …) are deliberately
// absent rather than faked with placeholder defaults. `description` and
// `link` are honest standalone fields populated from search-result
// metadata when available.
//
// Internal because `PodcastDetailContent.initial` names this type across
// files; init is fileprivate so `PodcastDetailSeed` remains the only
// constructor.
struct PodcastDetailInitialPodcast:
  PodcastListable,
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

  var id: FeedURL { feedURL }
  var toString: String { "(\(feedURL.toString)) - \(title)" }
  var searchableString: String { "\(title) - \(description)" }

  fileprivate init(savedSearchResult: SavedSearchResultPodcast) {
    podcastID = savedSearchResult.savedPodcast.id
    feedURL = savedSearchResult.savedPodcast.feedURL
    iTunesID = savedSearchResult.savedPodcast.iTunesID
    image = savedSearchResult.savedPodcast.image
    title = savedSearchResult.savedPodcast.title
    description = savedSearchResult.originalPodcast.description
    link = savedSearchResult.originalPodcast.link
    subscriptionDate = savedSearchResult.savedPodcast.subscriptionDate
  }

  fileprivate init(listablePodcast: ListablePodcast) {
    podcastID = listablePodcast.id
    feedURL = listablePodcast.feedURL
    iTunesID = listablePodcast.iTunesID
    image = listablePodcast.image
    title = listablePodcast.title
    description = ""
    link = nil
    subscriptionDate = listablePodcast.subscriptionDate
  }
}
