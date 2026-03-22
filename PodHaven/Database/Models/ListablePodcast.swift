// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import Tagged

// Lightweight podcast type for list views. Only decodes columns needed for
// list display, so .removeDuplicates() in Observatory filters out changes to
// detail-only columns like lastUpdate, defaultPlaybackRate, etc.
struct ListablePodcast: PodcastListable, FetchableRecord {
  let id: Podcast.ID
  let iTunesID: ITunesPodcastID?
  let feedURL: FeedURL
  let title: String
  let image: URL
  let description: String
  let subscriptionDate: Date?
  let creationDate: Date

  // MARK: - Stringable / Searchable

  var toString: String { "(\(feedURL.toString)) - \(title)" }
  var searchableString: String { "\(title) - \(description)" }

  // MARK: - FetchableRecord

  init(row: Row) throws {
    id = row[Podcast.Columns.id]
    iTunesID = row[Podcast.Columns.iTunesID] as ITunesPodcastID?
    feedURL = row[Podcast.Columns.feedURL]
    title = row[Podcast.Columns.title]
    image = row[Podcast.Columns.image]
    description = row[Podcast.Columns.description]
    subscriptionDate = row[Podcast.Columns.subscriptionDate]
    creationDate = row[Podcast.Columns.creationDate]
  }
}
