// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation

@dynamicMemberLookup
struct DisplayablePodcast:
  PodcastDisplayable,
  Identifiable,
  Stringable,
  Hashable,
  Sendable
{
  @DynamicInjected(\.repo) private var repo

  let podcast: any PodcastDisplayable

  init(_ podcast: any PodcastDisplayable) {
    Assert.precondition(
      !(podcast is DisplayablePodcast),
      "Cannot wrap an instance of itself as a DisplayablePodcast"
    )

    self.podcast = podcast
  }

  subscript<T>(dynamicMember keyPath: KeyPath<any PodcastDisplayable, T>) -> T {
    podcast[keyPath: keyPath]
  }

  // MARK: - Identifiable

  var id: FeedURL { feedURL }

  // MARK: - Hashable / Equatable

  func hash(into hasher: inout Hasher) {
    hasher.combine(podcast.feedURL)
  }

  static func == (lhs: DisplayablePodcast, rhs: DisplayablePodcast) -> Bool {
    lhs.feedURL == rhs.feedURL
  }

  // MARK: - Stringable

  var toString: String { podcast.toString }

  // MARK: - PodcastDisplayable

  var feedURL: FeedURL { podcast.feedURL }
  var image: URL { podcast.image }
  var title: String { podcast.title }
  var description: String { podcast.description }
  var link: URL? { podcast.link }
  var subscribed: Bool { podcast.subscribed }

  // MARK: - Helpers

  func getPodcast() -> Podcast? {
    podcast as? Podcast
  }

  func getUnsavedPodcast() -> UnsavedPodcast? {
    podcast as? UnsavedPodcast
  }
}
