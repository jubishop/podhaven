// Copyright Justin Bishop, 2026

import Foundation

struct PodcastCounts: Equatable {
  let subscribed: Int
  let unsubscribed: Int
  let byTag: [Tag.ID: Int]
}
