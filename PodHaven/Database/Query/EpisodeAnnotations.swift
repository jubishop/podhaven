// Copyright Justin Bishop, 2025

import Foundation
import GRDB

struct EpisodeAnnotations {
  static var inPodcast: QueryInterfaceRequest<Episode> {
    let podcastTable = TableAlias()
    _ = Podcast.aliased(podcastTable)
    return Episode.filter(Schema.podcastIDColumn == podcastTable[Schema.idColumn])
  }

  static let allUnfinished = inPodcast.filter(Schema.completedColumn == false)
  static let latestUnfinished = allUnfinished.select(max(Schema.pubDateColumn))

  static let allUnstarted = allUnfinished.filter(Schema.currentTimeColumn == 0)
  static let latestUnstarted = allUnstarted.select(max(Schema.pubDateColumn))

  static let allUnqueued = allUnstarted.filter(Schema.queueOrderColumn == nil)
  static let latestUnqueued = allUnqueued.select(max(Schema.pubDateColumn))
}
