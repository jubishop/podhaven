// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import IdentifiedCollections

struct PodcastEpisodeWithTags:
  Decodable,
  Equatable,
  FetchableRecord,
  Hashable,
  Identifiable
{
  var id: Episode.ID { podcastEpisode.id }

  let podcastEpisode: PodcastEpisode
  let tags: IdentifiedArrayOf<Tag>

  init(from decoder: any Decoder) throws {
    podcastEpisode = try PodcastEpisode(from: decoder)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let decodedTags = try container.decodeIfPresent([Tag].self, forKey: .tags) {
      tags = IdentifiedArrayOf(uniqueElements: decodedTags)
    } else {
      tags = []
    }
  }

  private enum CodingKeys: String, CodingKey {
    case tags
  }
}
