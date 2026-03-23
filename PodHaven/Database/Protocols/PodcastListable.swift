// Copyright Justin Bishop, 2026

import Foundation

protocol PodcastListable: PodcastFoundational, Hashable, Searchable {
  var iTunesID: ITunesPodcastID? { get }
  var image: URL { get }
  var subscriptionDate: Date? { get }

  var subscribed: Bool { get }
}

extension PodcastListable {
  var iTunesID: ITunesPodcastID? { nil }
  var subscribed: Bool { subscriptionDate != nil }
}
