// Copyright Justin Bishop, 2026

import AVFoundation
import Foundation
import GRDB
import Tagged

struct WidgetEpisode: Equatable, FetchableRecord, Identifiable {
  let id: Episode.ID
  let title: String
  let pubDate: Date
  let duration: CMTime
  let episodeImage: URL?
  let podcastImage: URL

  var image: URL { episodeImage ?? podcastImage }

  init(row: Row) throws {
    id = row[Episode.Columns.id]
    title = row[Episode.Columns.title]
    pubDate = row[Episode.Columns.pubDate]
    duration = row[Episode.Columns.duration]
    episodeImage = row[Episode.Columns.image]

    guard let podcastRow = row.scopes["podcast"] else {
      Assert.fatal("WidgetEpisode requires podcast scope via including(required:)")
    }
    podcastImage = podcastRow[Podcast.Columns.image]
  }
}
