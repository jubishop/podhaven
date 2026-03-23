// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Tagged

// Lightweight podcast type for list views. Only decodes columns needed for
// list display, so .removeDuplicates() in Observatory filters out changes to
// detail-only columns like lastUpdate, defaultPlaybackRate, etc.
struct ListablePodcast: PodcastListable, FetchableRecord {
  let id: Podcast.ID
  let creationDate: Date

  // MARK: - PodcastListable

  let feedURL: FeedURL
  let iTunesID: ITunesPodcastID?
  let image: URL
  let title: String
  let subscriptionDate: Date?

  // MARK: - Stringable / Searchable

  var toString: String { "(\(feedURL.toString)) - \(title)" }
  var searchableString: String { title }

  // MARK: - FetchableRecord

  init(row: Row) throws {
    id = row[Podcast.Columns.id]
    iTunesID = row[Podcast.Columns.iTunesID] as ITunesPodcastID?
    feedURL = row[Podcast.Columns.feedURL]
    title = row[Podcast.Columns.title]
    image = row[Podcast.Columns.image]
    subscriptionDate = row[Podcast.Columns.subscriptionDate]
    creationDate = row[Podcast.Columns.creationDate]
  }

  func getPodcast() async throws -> Podcast {
    let repo = Container.shared.repo()
    guard let podcastSeries = try await repo.podcastSeries(id) else {
      throw DatabaseError(message: "Podcast not found for ID \(id)")
    }
    return podcastSeries.podcast
  }
}
