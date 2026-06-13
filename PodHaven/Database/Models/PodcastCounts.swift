// Copyright Justin Bishop, 2026

import Foundation

struct PodcastCounts: Equatable {
  let subscribed: Int
  let unsubscribed: Int
  let untagged: Int
  let byTag: [Tag.ID: Int]
  let byFreshnessCadence: [FreshnessCadence: Int]
  let queueOnTop: Int
  let queueOnBottom: Int
  let autoCache: Int
  let autoSave: Int
  let notifyNewEpisodes: Int
}
