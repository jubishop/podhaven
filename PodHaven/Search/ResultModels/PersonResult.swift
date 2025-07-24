// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation
import IdentifiedCollections

struct PersonResult: Sendable, Decodable {
  struct ItemResult: Sendable, Decodable {
    let id: Int
    let guid: GUID
    let title: String
    @OptionalURL var link: URL?
    let description: String
    let datePublished: Date
    let enclosureUrl: MediaURL
    let duration: CMTime
    @OptionalURL var image: URL?
    let feedUrl: FeedURL
    @OptionalURL var feedImage: URL?
    let feedTitle: String

    func toUnsavedPodcastEpisode(merging podcastEpisode: PodcastEpisode? = nil) throws
      -> UnsavedPodcastEpisode
    {
      guard podcastEpisode == nil || podcastEpisode?.episode.media == enclosureUrl
      else {
        throw ParseError.mergingDifferentMediaURLs(
          parsing: enclosureUrl,
          merging: podcastEpisode?.episode.media
        )
      }

      guard podcastEpisode == nil || podcastEpisode?.podcast.feedURL == feedUrl
      else {
        throw ParseError.mergingDifferentFeedURLs(
          parsing: feedUrl,
          merging: podcastEpisode?.podcast.feedURL
        )
      }

      guard let feedImage = feedImage ?? podcastEpisode?.podcast.image
      else { throw ParseError.missingImage(title) }

      return UnsavedPodcastEpisode(
        unsavedPodcast: try UnsavedPodcast(
          feedURL: feedUrl,
          title: feedTitle,
          image: feedImage,
          description: podcastEpisode?.podcast.description ?? "",  // Not in PodcastIndex API
          link: link ?? podcastEpisode?.podcast.link,
          lastUpdate: podcastEpisode?.podcast.lastUpdate,
          subscriptionDate: podcastEpisode?.podcast.subscriptionDate
        ),
        unsavedEpisode: try UnsavedEpisode(
          guid: guid,
          media: enclosureUrl,
          title: title,
          pubDate: datePublished,
          duration: duration,
          description: description,
          image: image ?? podcastEpisode?.episode.image,
          completionDate: podcastEpisode?.episode.completionDate,
          currentTime: podcastEpisode?.episode.currentTime,
          queueOrder: podcastEpisode?.episode.queueOrder
        )
      )
    }
  }

  let items: [ItemResult]

  func toPodcastEpisodeArray(merging podcastSeries: IdentifiedArray<FeedURL, PodcastSeries>? = nil)
    -> IdentifiedArray<MediaURL, UnsavedPodcastEpisode>
  {
    IdentifiedArray(
      items.compactMap { item in
        guard let series = podcastSeries?[id: item.feedUrl],
          let episode = series.episodes[id: item.guid]
        else { return try? item.toUnsavedPodcastEpisode() }

        return try? item.toUnsavedPodcastEpisode(
          merging: PodcastEpisode(podcast: series.podcast, episode: episode)
        )
      },
      id: \.unsavedEpisode.media,
      uniquingIDsWith: { a, b in
        // Keep whichever is the newest
        a.unsavedEpisode.pubDate >= b.unsavedEpisode.pubDate ? a : b
      }
    )
  }
}
