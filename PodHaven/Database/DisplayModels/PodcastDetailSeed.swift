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

  // Both cases conform to `PodcastListable`, so list-row fields forward
  // through one existential. `description` and `link` aren't in the
  // listable surface — bridge has them as standalone fields, displayed has
  // them via `PodcastDisplayable` — so they switch explicitly.
  private var canonicalListable: any PodcastListable {
    switch self {
    case .initial(let podcast): return podcast
    case .loaded(let podcast): return podcast
    }
  }

  // MARK: - PodcastListable

  var id: FeedURL { feedURL }
  var podcastID: Podcast.ID? { canonicalListable.podcastID }
  var feedURL: FeedURL { canonicalListable.feedURL }
  var iTunesID: ITunesPodcastID? { canonicalListable.iTunesID }
  var image: URL { canonicalListable.image }
  var title: String { canonicalListable.title }
  var subscriptionDate: Date? { canonicalListable.subscriptionDate }
  var subscribed: Bool { canonicalListable.subscribed }
  var isSaved: Bool { canonicalListable.isSaved }
  var toString: String { canonicalListable.toString }

  // MARK: - Header extras (not in PodcastListable)

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
