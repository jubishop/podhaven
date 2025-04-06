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
  private let queue: Queue
  fileprivate init(_ appDB: AppDB) {
    self.appDB = appDB
    self.queue = Container.shared.queue()
  }

  // MARK: - Global Reader

  func allPodcasts(_ sqlExpression: SQLExpression? = nil) async throws -> [Podcast] {
    let request = Podcast.all().filtered(with: sqlExpression)
    return try await appDB.db.read { db in
      try request.fetchAll(db)
    }
  }

  func allPodcastSeries(_ sqlExpression: SQLExpression? = nil) async throws -> [PodcastSeries] {
    let request = Podcast.all().filtered(with: sqlExpression)
    return try await appDB.db.read { db in
      try request
        .including(all: Podcast.episodes)
        .asRequest(of: PodcastSeries.self)
        .fetchAll(db)
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
    guard !mediaURLs.isEmpty
    else { return [] }

    return try await appDB.db.read { db in
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
    try await episodes([media]).first
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
  func delete(_ podcastIDs: [Podcast.ID]) async throws -> Int {
    try await appDB.db.write { db in
      let queuedEpisodeIDs =
        try Episode
        .select(Schema.idColumn, as: Episode.ID.self)
        .filter(podcastIDs.contains(Schema.podcastIDColumn) && Schema.queueOrderColumn != nil)
        .fetchAll(db)
      try queue.dequeue(db, queuedEpisodeIDs, RepoAccessKey())

      return try Podcast.filter(ids: podcastIDs).deleteAll(db)
    }
  }

  @discardableResult
  func delete(_ podcastID: Podcast.ID) async throws -> Bool {
    try await delete([podcastID]) > 0
  }

  // MARK: - Episode Writers

  @discardableResult
  func upsertPodcastEpisodes(_ unsavedPodcastEpisodes: [UnsavedPodcastEpisode]) async throws
    -> [PodcastEpisode]
  {
    guard !unsavedPodcastEpisodes.isEmpty
    else { return [] }

    return try await appDB.db.write { db in
      var upsertedPodcasts: IdentifiedArray<FeedURL, Podcast> = IdentifiedArray(id: \.feedURL)

      return try unsavedPodcastEpisodes.map { unsavedPodcastEpisode in
        let podcast: Podcast
        if let upsertedPodcast = upsertedPodcasts[id: unsavedPodcastEpisode.unsavedPodcast.feedURL]
        {
          podcast = upsertedPodcast
        } else {
          podcast = try unsavedPodcastEpisode.unsavedPodcast.upsertAndFetch(db, as: Podcast.self)
          upsertedPodcasts.append(podcast)
        }

        var newUnsavedEpisode = unsavedPodcastEpisode.unsavedEpisode
        newUnsavedEpisode.podcastId = podcast.id
        let episode = try newUnsavedEpisode.upsertAndFetch(db, as: Episode.self)
        return PodcastEpisode(podcast: podcast, episode: episode)
      }
    }
  }

  @discardableResult
  func upsertPodcastEpisode(_ unsavedPodcastEpisode: UnsavedPodcastEpisode) async throws
    -> PodcastEpisode
  {
    let podcastEpisodes = try await upsertPodcastEpisodes([unsavedPodcastEpisode])
    guard let podcastEpisode = podcastEpisodes.first
    else { fatalError("upsertPodcastEpisode returned no entries somehow") }

    return podcastEpisode
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

  @discardableResult
  func markSubscribed(_ podcastIDs: [Podcast.ID]) async throws -> Int {
    try await _setSubscribedColumn(podcastIDs, to: true)
  }

  @discardableResult
  func markSubscribed(_ podcastID: Podcast.ID) async throws -> Bool {
    try await markSubscribed([podcastID]) > 0
  }

  @discardableResult
  func markUnsubscribed(_ podcastIDs: [Podcast.ID]) async throws -> Int {
    try await _setSubscribedColumn(podcastIDs, to: false)
  }

  @discardableResult
  func markUnsubscribed(_ podcastID: Podcast.ID) async throws -> Bool {
    try await markUnsubscribed([podcastID]) > 0
  }

  // MARK: Private Helpers

  private func _setSubscribedColumn(_ podcastIDs: [Podcast.ID], to subscribed: Bool) async throws
    -> Int
  {
    try await appDB.db.write { db in
      try Podcast
        .filter(podcastIDs.contains(Schema.idColumn))
        .updateAll(db, Schema.subscribedColumn.set(to: subscribed))
    }
  }
}
