// Copyright Justin Bishop, 2026

import Foundation

struct PodcastDetailContent: PodcastDisplayable, Hashable, Sendable {
  let podcastID: Podcast.ID?
  let feedURL: FeedURL
  let iTunesID: ITunesPodcastID?
  let image: URL
  let title: String
  let subscriptionDate: Date?
  let toString: String
  let searchableString: String
  let description: String
  let link: URL?
  let loaded: DisplayedPodcast?

  var id: FeedURL { feedURL }

  init(initial listed: ListedPodcast) {
    podcastID = listed.podcastID
    feedURL = listed.feedURL
    iTunesID = listed.iTunesID
    image = listed.image
    title = listed.title
    subscriptionDate = listed.subscriptionDate
    toString = listed.toString
    searchableString = listed.searchableString
    description = listed.description
    link = listed.link
    loaded = nil
  }

  init(loaded displayed: DisplayedPodcast) {
    podcastID = displayed.podcastID
    feedURL = displayed.feedURL
    iTunesID = displayed.iTunesID
    image = displayed.image
    title = displayed.title
    subscriptionDate = displayed.subscriptionDate
    toString = displayed.toString
    searchableString = displayed.searchableString
    description = displayed.description
    link = displayed.link
    loaded = displayed
  }
}
