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
      // Unsaved search results carry an `UnsavedPodcast` with the full header
      // (description/link) — promote straight to `.loaded` so the detail view
      // never has to flip through a non-displayable initial state.
      if let unsavedPodcast = listedPodcast.unsavedSearchResult {
        return PodcastDetailPresentation(
          podcast: .loaded(DisplayedPodcast(unsavedPodcast)),
          episodes: []
        )
      }
      return PodcastDetailPresentation(
        podcast: .initial(listedPodcast),
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
}

// Live state of `PodcastDetailViewModel.podcast`. `.initial` is the
// transient list-row snapshot displayed before the saved series hydrates;
// `.loaded` is the fully-displayable podcast (saved or unsaved). Both arms
// conform to `PodcastDisplayable`, so a single existential helper forwards
// every header field. Settings (`defaultPlaybackRate`, `queueAllEpisodes`, …)
// live on `PodcastSettings` and are accessible only via the `.loaded` case —
// `ListedPodcast` doesn't claim to have them.
enum PodcastDetailContent: PodcastDisplayable, Hashable, Sendable {
  case initial(ListedPodcast)
  case loaded(DisplayedPodcast)

  var loaded: DisplayedPodcast? {
    guard case .loaded(let podcast) = self else { return nil }
    return podcast
  }

  private var canonical: any PodcastDisplayable {
    switch self {
    case .initial(let podcast): return podcast
    case .loaded(let podcast): return podcast
    }
  }

  // MARK: - PodcastListable

  var id: FeedURL { feedURL }
  var podcastID: Podcast.ID? { canonical.podcastID }
  var feedURL: FeedURL { canonical.feedURL }
  var iTunesID: ITunesPodcastID? { canonical.iTunesID }
  var image: URL { canonical.image }
  var title: String { canonical.title }
  var subscriptionDate: Date? { canonical.subscriptionDate }
  var toString: String { canonical.toString }
  var searchableString: String { canonical.searchableString }

  // MARK: - PodcastDisplayable

  var description: String { canonical.description }
  var link: URL? { canonical.link }
}
