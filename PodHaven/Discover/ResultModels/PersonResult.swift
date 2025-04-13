// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

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
      precondition(
        podcastEpisode == nil || podcastEpisode?.episode.media == enclosureUrl,
        """
        Merging two podcastEpisodes with different mediaURLs?: \
        \(String(describing: podcastEpisode?.episode.media)), \(enclosureUrl)
        """
      )

      guard podcastEpisode == nil || podcastEpisode?.podcast.feedURL == feedUrl
      else {
        throw Err.msg(
          """
          Merging two podcastEpisodes with different feedURLs?: \
          \(String(describing: podcastEpisode?.podcast.feedURL)), \(feedUrl)
          """
        )
      }

      guard let feedImage = feedImage ?? podcastEpisode?.podcast.image
      else { throw Err.msg("No image for \(title)") }

      return UnsavedPodcastEpisode(
        unsavedPodcast: try UnsavedPodcast(
          feedURL: feedUrl,
          title: feedTitle,
          image: feedImage,
          description: podcastEpisode?.podcast.description ?? "",  // Not in PodcastIndex API
          link: link ?? podcastEpisode?.podcast.link,
          lastUpdate: podcastEpisode?.podcast.lastUpdate,
          subscribed: podcastEpisode?.podcast.subscribed
        ),
        unsavedEpisode: try UnsavedEpisode(
          guid: guid,
          media: enclosureUrl,
          title: title,
          pubDate: datePublished,
          duration: duration,
          description: description,
          image: image ?? podcastEpisode?.episode.image,
          completed: podcastEpisode?.episode.completed,
          currentTime: podcastEpisode?.episode.currentTime,
          queueOrder: podcastEpisode?.episode.queueOrder
        )
      )
    }
  }
  let items: [ItemResult]
}
