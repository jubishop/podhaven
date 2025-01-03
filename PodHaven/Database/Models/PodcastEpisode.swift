// Copyright Justin Bishop, 2025

import Foundation
import GRDB
import IdentifiedCollections

typealias PodcastEpisodeArray = IdentifiedArray<URL, PodcastEpisode>

struct PodcastEpisode: Codable, FetchableRecord, Equatable, Identifiable,
  Hashable
{
  var id: Int64 { episode.id }

  let podcast: Podcast
  let episode: Episode
}
