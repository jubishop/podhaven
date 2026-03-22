// Copyright Justin Bishop, 2026

import Foundation

protocol PodcastListable: PodcastFoundational, Searchable {
  var iTunesID: ITunesPodcastID? { get }
  var image: URL { get }
  var description: String { get }
  var subscriptionDate: Date? { get }
  var subscribed: Bool { get }
}

extension PodcastListable {
  var subscribed: Bool { subscriptionDate != nil }
}
