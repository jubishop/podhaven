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

    func toUnsavedPodcastEpisode() throws -> UnsavedPodcastEpisode {
      guard let feedImage = feedImage
      else { throw Err.msg("No image for \(title)") }

      return UnsavedPodcastEpisode(
        unsavedPodcast: try UnsavedPodcast(
          feedURL: feedUrl,
          title: feedTitle,
          image: feedImage,
          description: "", // Not provided by PodcastIndex API
          link: link
        ),
        unsavedEpisode: try UnsavedEpisode(
          guid: guid,
          media: enclosureUrl,
          title: title,
          pubDate: datePublished,
          duration: duration,
          description: description,
          image: image
        )
      )
    }
  }
  let items: [ItemResult]
}
