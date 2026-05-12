// Copyright Justin Bishop, 2026

import Foundation

// View-facing projection of `PodcastDetailViewModel.state`. `.initial` is the
// transient list-row snapshot displayed before the saved series hydrates;
// `.loaded` is the fully-displayable podcast (saved or unsaved). Both arms
// conform to `PodcastDisplayable`, so a single existential helper forwards
// every header field. Settings (`defaultPlaybackRate`, `queueAllEpisodes`, …)
// live on `DisplayedPodcast.settings` and are reachable only via the `.loaded`
// case — `ListedPodcast` doesn't claim to have them.
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
