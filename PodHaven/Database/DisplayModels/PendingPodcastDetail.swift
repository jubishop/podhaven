// Copyright Justin Bishop, 2026

import Foundation

struct PendingPodcastDetail:
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

  var id: FeedURL { feedURL }
  var toString: String { "(\(feedURL.toString)) - \(title)" }
  var searchableString: String { "\(title) - \(description)" }

  init(_ listedPodcast: ListedPodcast) {
    if let unsavedPodcast = listedPodcast.getUnsavedPodcast() {
      podcastID = unsavedPodcast.podcastID
      feedURL = unsavedPodcast.feedURL
      iTunesID = unsavedPodcast.iTunesID
      image = unsavedPodcast.image
      title = unsavedPodcast.title
      description = unsavedPodcast.description
      link = unsavedPodcast.link
      subscriptionDate = unsavedPodcast.subscriptionDate
      defaultPlaybackRate = unsavedPodcast.defaultPlaybackRate
      queueAllEpisodes = unsavedPodcast.queueAllEpisodes
      cacheAllEpisodes = unsavedPodcast.cacheAllEpisodes
      notifyNewEpisodes = unsavedPodcast.notifyNewEpisodes
    } else if let searchResult = listedPodcast.getSearchResultPodcast() {
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
    } else if let listablePodcast = listedPodcast.getListablePodcast() {
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
    } else {
      Assert.fatal("Cannot build PendingPodcastDetail from: \(type(of: listedPodcast.podcast))")
    }
  }
}
