// Copyright Justin Bishop, 2024

import AVFoundation
import Foundation
import GRDB
import IdentifiedCollections

typealias PodcastArray = IdentifiedArray<URL, Podcast>

struct Repo: Sendable {
  #if DEBUG
    static func empty() -> Repo { Repo(.empty()) }
  #endif

  static let shared = Repo(.shared)

  var db: any DatabaseReader { appDB.db }

  private let appDB: AppDB
  let observer: SharedValueObservation<PodcastArray>

  init(_ appDB: AppDB) {
    self.appDB = appDB
    self.observer =
      ValueObservation
      .tracking { db in
        try Podcast.all().fetchIdentifiedArray(db, id: \Podcast.feedURL)
      }
      .removeDuplicates()
      .shared(in: appDB.db)
  }

  // MARK: - Readers

  func allPodcasts() async throws -> PodcastArray {
    try await appDB.db.read { db in
      try Podcast.all().fetchIdentifiedArray(db, id: \Podcast.feedURL)
    }
  }

  // MARK: - Series Writers

  @discardableResult
  func insertSeries(
    _ unsavedPodcast: UnsavedPodcast,
    unsavedEpisodes: [UnsavedEpisode] = []
  ) async throws -> Podcast {
    try await appDB.db.write { db in
      let podcast = try unsavedPodcast.insertAndFetch(db, as: Podcast.self)
      for var unsavedEpisode in unsavedEpisodes {
        unsavedEpisode.podcastId = podcast.id
        try unsavedEpisode.insert(db)
      }
      return podcast
    }
  }

  func insertSeries(
    _ podcast: Podcast,
    unsavedEpisodes: [UnsavedEpisode] = [],
    existingEpisodes: [Episode] = []
  ) async throws {
    try await appDB.db.write { db in
      try podcast.update(db)
      for existingEpisode in existingEpisodes {
        try existingEpisode.update(db)
      }
      for var unsavedEpisode in unsavedEpisodes {
        unsavedEpisode.podcastId = podcast.id
        try unsavedEpisode.insert(db)
      }
    }
  }

  // MARK: - Podcast Writers

  @discardableResult
  func delete(_ podcast: Podcast) async throws -> Bool {
    try await appDB.db.write { db in
      try podcast.delete(db)
    }
  }

  // MARK: - Episode Writers

  func updateCurrentTime(_ episodeID: Int64, _ currentTime: CMTime) async throws
  {
    try await appDB.db.write { db in
      guard var episode = try Episode.fetchOne(db, id: episodeID)
      else { return }

      episode.currentTime = currentTime
      try episode.update(db)
    }
  }
}
