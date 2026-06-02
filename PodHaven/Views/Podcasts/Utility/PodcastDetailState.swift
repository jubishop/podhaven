// Copyright Justin Bishop, 2025

import Foundation
import IdentifiedCollections

enum PodcastDetailState: Equatable, Sendable, Stringable {
  case initial(ListedPodcast)
  case unsaved(UnsavedPodcast, episodes: IdentifiedArrayOf<UnsavedEpisode>)
  case saved(PodcastSeriesDetail)

  var savedSeries: PodcastSeriesDetail? {
    guard case .saved(let series) = self else { return nil }
    return series
  }

  var detailContent: PodcastDetailContent {
    switch self {
    case .initial(let listed): return PodcastDetailContent(initial: listed)
    case .unsaved(let unsavedPodcast, _):
      return PodcastDetailContent(loaded: DisplayedPodcast(unsavedPodcast))
    case .saved(let series): return PodcastDetailContent(loaded: DisplayedPodcast(series.podcast))
    }
  }

  var feedURL: FeedURL {
    switch self {
    case .initial(let listed): return listed.feedURL
    case .unsaved(let unsavedPodcast, _): return unsavedPodcast.feedURL
    case .saved(let series): return series.podcast.feedURL
    }
  }

  var iTunesID: ITunesPodcastID? {
    switch self {
    case .initial(let listed): return listed.iTunesID
    case .unsaved(let unsavedPodcast, _): return unsavedPodcast.iTunesID
    case .saved(let series): return series.podcast.iTunesID
    }
  }

  var toString: String {
    switch self {
    case .initial(let listed): return "initial(\(listed.toString))"
    case .unsaved(let unsavedPodcast, let episodes):
      return "unsaved(\(unsavedPodcast.toString), episodes: \(episodes.count))"
    case .saved(let series): return "saved(\(series.toString))"
    }
  }
}
