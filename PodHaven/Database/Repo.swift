// Copyright Justin Bishop, 2025

import AVFoundation
import Factory
import Foundation
import GRDB
import IdentifiedCollections
import Tagged

typealias RequestClosure =
  @Sendable (QueryInterfaceRequest<Podcast>) -> QueryInterfaceRequest<Podcast>

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

  // MARK: - Global Reader

  func allPodcasts(_ requestClosure: (@escaping RequestClosure) = { $0 }) async throws
    -> PodcastArray
  {
    try await appDB.db.read { db in
      try requestClosure(Podcast.all())
        .fetchIdentifiedArray(db, id: \.feedURL)
    }
  }

  func allPodcastSeries(_ requestClosure: (@escaping RequestClosure) = { $0 }) async throws
    -> PodcastSeriesArray
  {
    try await appDB.db.read { db in
      try requestClosure(Podcast.all())
        .including(all: Podcast.episodes)
        .asRequest(of: PodcastSeries.self)
        .fetchIdentifiedArray(db, id: \.podcast.feedURL)
    }
  }

  // MARK: - Series Readers

  func podcastSeries(_ podcastID: Podcast.ID) async throws -> PodcastSeries? {
    try await appDB.db.read { db in
      try Podcast
        .filter(id: podcastID)
        .including(all: Podcast.episodes)
        .asRequest(of: PodcastSeries.self)
        .fetchOne(db)
    }
  }

  func podcastSeries(_ feedURL: FeedURL) async throws -> PodcastSeries? {
    try await appDB.db.read { db in
      try Podcast
        .filter(Schema.feedURLColumn == feedURL)
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

  func episodes(_ mediaURLs: [MediaURL]) async throws -> [PodcastEpisode] {
    try await appDB.db.read { db in
      let episodes =
        try Episode
        .filter(mediaURLs.contains(Schema.mediaColumn))
        .fetchAll(db)

      let podcasts =
        try Podcast
        .filter(Set(episodes.map(\.podcastId)).contains(Schema.idColumn))
        .fetchIdentifiedArray(db, id: \.id)

      return episodes.compactMap { episode in
        guard let podcastId = episode.podcastId, let podcast = podcasts[id: podcastId]
        else { return nil }

        return PodcastEpisode(podcast: podcast, episode: episode)
      }
    }
  }

  func episode(_ media: MediaURL) async throws -> PodcastEpisode? {
    try await episodes(Array([media])).first
  }

  // MARK: - Series Writers

  @discardableResult
  func insertSeries(_ unsavedPodcast: UnsavedPodcast, unsavedEpisodes: [UnsavedEpisode] = [])
    async throws -> PodcastSeries
  {
    try await appDB.db.write { db in
      let podcast = try unsavedPodcast.insertAndFetch(db, as: Podcast.self)
      var episodes: IdentifiedArray<GUID, Episode> = IdentifiedArray(id: \.guid)
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

  // TODO: Remove this
  @discardableResult
  func addEpisode(_ unsavedPodcastEpisode: UnsavedPodcastEpisode) async throws -> PodcastEpisode {
    let unsavedPodcast = unsavedPodcastEpisode.unsavedPodcast

    return try await appDB.db.write { db in
      var unsavedEpisode = unsavedPodcastEpisode.unsavedEpisode
      let podcast: Podcast = try fetchOrInsert(db, unsavedPodcast)
      unsavedEpisode.podcastId = podcast.id
      let episode = try unsavedEpisode.insertAndFetch(db, as: Episode.self)
      return PodcastEpisode(podcast: podcast, episode: episode)
    }
  }

  // TODO: Test this
  func fetchOrInsertEpisodes(_ unsavedPodcastEpisodes: [UnsavedPodcastEpisode]) async throws
    -> [PodcastEpisode]
  {
    try await appDB.db.write { db in
      var existingPodcasts =
        try Podcast
        .filter(
          Set(unsavedPodcastEpisodes.map(\.unsavedPodcast.feedURL)).contains(Schema.feedURLColumn)
        )
        .fetchIdentifiedArray(db, id: \.feedURL)

      var existingEpisodes =
        try Episode
        .filter(
          Set(unsavedPodcastEpisodes.map(\.unsavedEpisode.media)).contains(Schema.mediaColumn)
        )
        .fetchIdentifiedArray(db, id: \.media)

      return try unsavedPodcastEpisodes.map { unsavedPodcastEpisode in
        let podcast: Podcast
        if let existingPodcast = existingPodcasts[id: unsavedPodcastEpisode.unsavedPodcast.feedURL]
        {
          podcast = existingPodcast
        } else {
          podcast = try unsavedPodcastEpisode.unsavedPodcast.insertAndFetch(db, as: Podcast.self)
          existingPodcasts.append(podcast)
        }

        let episode: Episode
        if let existingEpisode = existingEpisodes[id: unsavedPodcastEpisode.unsavedEpisode.media] {
          episode = existingEpisode
        } else {
          var newUnsavedEpisode = unsavedPodcastEpisode.unsavedEpisode
          newUnsavedEpisode.podcastId = podcast.id
          episode = try newUnsavedEpisode.insertAndFetch(db, as: Episode.self)
          existingEpisodes.append(episode)
        }
        return PodcastEpisode(podcast: podcast, episode: episode)
      }
    }
  }

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

  func markSubscribed(_ podcastID: Podcast.ID) async throws {
    _ = try await appDB.db.write { db in
      try Podcast
        .filter(id: podcastID)
        .updateAll(db, Schema.subscribedColumn.set(to: true))
    }
  }

  // MARK: Private Helpers

  // TODO: Remove this
  private func fetchOrInsert(_ db: Database, _ unsavedPodcast: UnsavedPodcast) throws -> Podcast {
    guard
      let podcast = try Podcast.filter(Schema.feedURLColumn == unsavedPodcast.feedURL).fetchOne(db)
    else { return try unsavedPodcast.insertAndFetch(db, as: Podcast.self) }

    return podcast
  }
}
