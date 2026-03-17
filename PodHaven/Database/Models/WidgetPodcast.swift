// Copyright Justin Bishop, 2026

import Foundation
import GRDB

struct WidgetPodcast: Equatable, FetchableRecord {
  let feedURL: FeedURL
  let title: String
  let image: URL

  init(row: Row) throws {
    feedURL = row[Podcast.Columns.feedURL]
    title = row[Podcast.Columns.title]
    image = row[Podcast.Columns.image]
  }
}
