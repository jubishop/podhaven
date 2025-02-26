// Copyright Justin Bishop, 2025

import Foundation
import GRDB
import IdentifiedCollections
import Tagged

typealias PodcastEpisodeArray = IdentifiedArray<MediaURL, PodcastEpisode>

struct PodcastEpisode: Codable, EpisodeRepresentable, Equatable, FetchableRecord, Identifiable {
  var id: Episode.ID { episode.id }

  // MARK: - EpisodeRepresentable

  var title: String { episode.title }

  // MARK: - Data

  let podcast: Podcast
  let episode: Episode
}
