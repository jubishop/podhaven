// Copyright Justin Bishop, 2025

import AVFoundation
import Factory
import Foundation
import GRDB
import IdentifiedCollections
import Tagged

extension Container {
  var repo: Factory<Repo> {
    Factory(self) { Repo(.onDisk(RepoAccessKey())) }.scope(.singleton)
  }
}

struct RepoAccessKey { fileprivate init() {} }

struct Repo: Sendable {
  #if DEBUG
    static func inMemory() -> Repo { Repo(.inMemory()) }
    static func initForTest(_ appDB: AppDB) -> Repo { Repo(appDB) }
  #endif

  // MARK: - Initialization

  var db: any DatabaseReader { appDB.db }
  private let appDB: AppDB
  fileprivate init(_ appDB: AppDB) {
    self.appDB = appDB
  }

  // MARK: - Global Readers

  func allPodcasts() async throws -> PodcastArray {
    try await appDB.db.read { db in
      try Podcast
        .all()
        .fetchIdentifiedArray(db, id: \Podcast.feedURL)
    }
  }

  func allSubscribedPodcasts() async throws -> PodcastArray {
    try await appDB.db.read { db in
      try Podcast
        .filter(Schema.subscribedColumn == true)
        .fetchIdentifiedArray(db, id: \Podcast.feedURL)
    }
  }

  func allPodcastSeries() async throws -> PodcastSeriesArray {
    try await appDB.db.read { db in
      try Podcast
        .all()
        .including(all: Podcast.episodes)
        .asRequest(of: PodcastSeries.self)
        .fetchIdentifiedArray(db, id: \PodcastSeries.podcast.feedURL)
    }
  }

  func allSubscribedPodcastSeries() async throws -> PodcastSeriesArray {
    try await appDB.db.read { db in
      try Podcast
        .filter(Schema.subscribedColumn == true)
        .including(all: Podcast.episodes)
        .asRequest(of: PodcastSeries.self)
        .fetchIdentifiedArray(db, id: \PodcastSeries.podcast.feedURL)
    }
  }

  func allStaleSubscribedPodcastSeries() async throws -> PodcastSeriesArray {
    try await appDB.db.read { db in
      try Podcast
        .filter(Schema.lastUpdateColumn < Date().addingTimeInterval(-600))  // 10 minutes
        .filter(Schema.subscribedColumn == true)
        .including(all: Podcast.episodes)
        .asRequest(of: PodcastSeries.self)
        .fetchIdentifiedArray(db, id: \PodcastSeries.podcast.feedURL)
    }
  }

  // MARK: - Series Readers

  func podcastSeries(podcastID: Podcast.ID) async throws -> PodcastSeries? {
    try await appDB.db.read { db in
      try Podcast
        .filter(id: podcastID)
        .including(all: Podcast.episodes)
        .asRequest(of: PodcastSeries.self)
        .fetchOne(db)
    }
  }

  // MARK: - Episode Readers

  func nextEpisode() async throws -> PodcastEpisode? {
    try await appDB.db.read { db in
      try Episode
        .filter(Schema.queueOrderColumn == 0)
        .including(required: Episode.podcast)
        .asRequest(of: PodcastEpisode.self)
        .fetchOne(db)
    }
  }

  func episode(_ episodeID: Episode.ID) async throws -> PodcastEpisode? {
    try await appDB.db.read { db in
      try Episode
        .filter(id: episodeID)
        .including(required: Episode.podcast)
        .asRequest(of: PodcastEpisode.self)
        .fetchOne(db)
    }
  }

  func episode(_ url: URL) async throws -> PodcastEpisode? {
    try await appDB.db.read { db in
      try Episode
        .filter(Schema.mediaColumn == url)
        .including(required: Episode.podcast)
        .asRequest(of: PodcastEpisode.self)
        .fetchOne(db)
    }
  }

  // MARK: - Series Writers

  @discardableResult
  func insertSeries(_ unsavedPodcast: UnsavedPodcast, unsavedEpisodes: [UnsavedEpisode] = [])
    async throws -> PodcastSeries
  {
    try await appDB.db.write { db in
      let podcast = try unsavedPodcast.insertAndFetch(db, as: Podcast.self)
      var episodes: EpisodeArray = IdentifiedArray(id: \Episode.guid)
      for var unsavedEpisode in unsavedEpisodes {
        unsavedEpisode.podcastId = podcast.id
        episodes.append(try unsavedEpisode.insertAndFetch(db, as: Episode.self))
      }
      return PodcastSeries(podcast: podcast, episodes: episodes)
    }
  }

  func updateSeries(
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
  func delete(_ podcastID: Podcast.ID) async throws -> Bool {
    try await appDB.db.write { db in
      try Podcast.deleteOne(db, id: podcastID)
    }
  }

  // MARK: - Episode Writers

  func updateCurrentTime(_ episodeID: Episode.ID, _ currentTime: CMTime) async throws {
    _ = try await appDB.db.write { db in
      try Episode
        .filter(id: episodeID)
        .updateAll(db, Schema.currentTimeColumn.set(to: currentTime.seconds))
    }
  }

  func markComplete(_ episodeID: Episode.ID) async throws {
    _ = try await appDB.db.write { db in
      try Episode
        .filter(id: episodeID)
        .updateAll(db, Schema.completedColumn.set(to: true), Schema.currentTimeColumn.set(to: 0))
    }
  }

  // TODO: Test this
  func markSubscribed(_ podcastID: Podcast.ID) async throws {
    _ = try await appDB.db.write { db in
      try Podcast
        .filter(id: podcastID)
        .updateAll(db, Schema.subscribedColumn.set(to: true))
    }
  }
}
