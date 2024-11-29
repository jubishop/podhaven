// Copyright Justin Bishop, 2024

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of Podcast model tests")
actor PodcastTests {
  private let db: AppDatabase

  init() {
    db = AppDatabase.empty()
  }

  @Test("that a podcast can be created")
  func createSinglePodcast() async throws {
    let url = URL(string: "https://example.com/data")!
    try db.write { db in
      let unsavedPodcast = UnsavedPodcast(feedURL: url, title: "Title")

      var podcast = try unsavedPodcast.insertAndFetch(db, as: Podcast.self)
      #expect(podcast.title == unsavedPodcast.title)

      let fetchedPodcast = try Podcast.find(db, id: podcast.id)
      #expect(fetchedPodcast == podcast)

      let filteredPodcast =
        try Podcast.filter(Column("title") == podcast.title).fetchOne(db)
      #expect(filteredPodcast == podcast)

      podcast.title = "New Title"
      try podcast.update(db)

      let fetchedUpdatedPodcast = try Podcast.find(db, id: podcast.id)
      #expect(fetchedUpdatedPodcast == podcast)

      let updatedFilteredPodcast =
        try Podcast.filter(Column("title") == podcast.title).fetchOne(db)
      #expect(updatedFilteredPodcast == podcast)

      let urlFilteredPodcast =
        try Podcast.filter(Column("feedURL") == url).fetchOne(db)
      #expect(urlFilteredPodcast == podcast)

      let fetchedAllPodcasts = try Podcast.fetchAll(db)
      #expect(fetchedAllPodcasts == [podcast])

      #expect(try podcast.exists(db))
      let deleted = try podcast.delete(db)
      #expect(deleted)
      #expect(!(try podcast.exists(db)))

      let noPodcasts = try Podcast.fetchAll(db)
      #expect(noPodcasts.isEmpty)

      let allCount = try Podcast.fetchCount(db)
      #expect(allCount == 0)

      let titleCount =
        try Podcast.filter(Column("title") == podcast.title).fetchCount(db)
      #expect(titleCount == 0)
    }
  }
}
