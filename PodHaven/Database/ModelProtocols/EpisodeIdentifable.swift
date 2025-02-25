// Copyright Justin Bishop, 2025

import Foundation

protocol EpisodeIdentifiable: Identifiable, Hashable {
  var id: Episode.ID { get }
  var title: String { get }
}
