// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Tagged

extension Container {
  var repo: Factory<Repo> {
    Factory(self) { Repo(self.appDB()) }.scope(.cached)
  }
}

struct Repo {
  @DynamicInjected(\.queue) private var queue

  private let log = Log.as(LogSubsystem.Database.repo)

  // MARK: - Initialization

  var db: any DatabaseReader { appDB.db }
  private let appDB: AppDB
  fileprivate init(_ appDB: AppDB) {
    self.appDB = appDB
  }

  // MARK: - Global Readers

  func allPodcasts(_ filter: SQLExpression = AppDB.NoOp) async throws -> [Podcast] {
    let request = Podcast.all().filter(filter)
    return try await appDB.db.read { db in
      try request.fetchAll(db)
    }
  }

  func allPodcastSeries(_ filter: SQLExpression = AppDB.NoOp) async throws(RepoError)
    -> [PodcastSeries]
  {
    do {
      let request = Podcast.all().filter(filter)
      return try await appDB.db.read { db in
        try request
          .including(all: Podcast.episodes)
          .asRequest(of: PodcastSeries.self)
          .fetchAll(db)
      }
    } catch {
      throw RepoError.readAllFailure(type: PodcastSeries.self, filter: filter, caught: error)
    }
  }

  // MARK: - Series Readers

  func podcastSeries(_ podcastID: Podcast.ID) async throws(RepoError) -> PodcastSeries? {
    do {
      return try await appDB.db.read { db in
        try Podcast
          .withID(podcastID)
          .including(all: Podcast.episodes)
          .asRequest(of: PodcastSeries.self)
          .fetchOne(db)
      }
    } catch {
      throw RepoError.readFailure(type: Podcast.self, id: podcastID.rawValue, caught: error)
    }
  }

  func podcastSeries(_ feedURL: FeedURL) async throws -> PodcastSeries? {
    try await appDB.db.read { db in
      try Podcast
        .filter { $0.feedURL == feedURL }
        .including(all: Podcast.episodes)
        .asRequest(of: PodcastSeries.self)
        .fetchOne(db)
    }
  }

  // MARK: - Episode Readers

  func episode(_ episodeID: Episode.ID) async throws -> PodcastEpisode? {
    try await appDB.db.read { db in
      try Episode
        .withID(episodeID)
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
        .filter { mediaURLs.contains($0.media) }
        .fetchAll(db)

      let podcasts =
        try Podcast
        .withIDs(episodes.map(\.podcastID))
        .fetchIdentifiedArray(db, id: \.id)

      return episodes.compactMap { episode in
        guard let podcast = podcasts[id: episode.podcastID]
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
    async throws(RepoError) -> PodcastSeries
  {
    do {
      return try await appDB.db.write { db in
        let podcast = try unsavedPodcast.insertAndFetch(db, as: Podcast.self)
        var episodes: IdentifiedArray<GUID, Episode> = IdentifiedArray(id: \.guid)
        for var unsavedEpisode in unsavedEpisodes {
          unsavedEpisode.podcastId = podcast.id
          episodes.append(try unsavedEpisode.insertAndFetch(db, as: Episode.self))
        }
        return PodcastSeries(podcast: podcast, episodes: episodes)
      }
    } catch {
      throw RepoError.insertFailure(
        type: PodcastSeries.self,
        description: "PodcastSeries with title: \(unsavedPodcast.title)",
        caught: error
      )
    }
  }

  func updateSeries(
    _ podcast: Podcast,
    unsavedEpisodes: [UnsavedEpisode] = [],
    existingEpisodes: [Episode] = []
  ) async throws(RepoError) {
    do {
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
    } catch {
      throw RepoError.updateFailure(
        type: PodcastSeries.self,
        id: podcast.id.rawValue,
        description: podcast.toString,
        caught: error
      )
    }
  }

  // MARK: - Podcast Writers

  @discardableResult
  func delete(_ podcastIDs: [Podcast.ID]) async throws -> Int {
    try await appDB.db.write { db in
      let queuedEpisodeIDs =
        try Episode.all()
        .queued()
        .filter { podcastIDs.contains($0.podcastId) }
        .selectID()
        .fetchAll(db)
      try queue.dequeue(db, queuedEpisodeIDs)

      return try Podcast.withIDs(podcastIDs).deleteAll(db)
    }
  }

  @discardableResult
  func delete(_ podcastID: Podcast.ID) async throws -> Bool {
    try await delete([podcastID]) > 0
  }

  // MARK: - Episode Writers

  @discardableResult
  func upsertPodcastEpisodes(_ unsavedPodcastEpisodes: [UnsavedPodcastEpisode])
    async throws(RepoError) -> [PodcastEpisode]
  {
    guard !unsavedPodcastEpisodes.isEmpty
    else { return [] }

    do {
      return try await appDB.db.write { db in
        var upsertedPodcasts: IdentifiedArray<FeedURL, Podcast> = IdentifiedArray(id: \.feedURL)

        return try unsavedPodcastEpisodes.map { unsavedPodcastEpisode in
          let podcast: Podcast
          if let upsertedPodcast = upsertedPodcasts[
            id: unsavedPodcastEpisode.unsavedPodcast.feedURL
          ] {
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
    } catch {
      throw RepoError.upsertFailure(
        type: PodcastEpisode.self,
        description: unsavedPodcastEpisodes.map(\.toString).joined(separator: ","),
        caught: error
      )
    }
  }

  @discardableResult
  func upsertPodcastEpisode(_ unsavedPodcastEpisode: UnsavedPodcastEpisode) async throws(RepoError)
    -> PodcastEpisode
  {
    let podcastEpisodes = try await upsertPodcastEpisodes([unsavedPodcastEpisode])
    guard let podcastEpisode = podcastEpisodes.first
    else { Assert.fatal("upsertPodcastEpisode returned no entries somehow") }

    return podcastEpisode
  }

  @discardableResult
  func updateDuration(_ episodeID: Episode.ID, _ duration: CMTime) async throws -> Bool {
    try await appDB.db.write { db in
      try Episode
        .withID(episodeID)
        .updateAll(db, Episode.Columns.duration.set(to: duration))
    } > 0
  }

  @discardableResult
  func updateCurrentTime(_ episodeID: Episode.ID, _ currentTime: CMTime) async throws -> Bool {
    try await appDB.db.write { db in
      try Episode
        .withID(episodeID)
        .updateAll(db, Episode.Columns.currentTime.set(to: currentTime))
    } > 0
  }

  @discardableResult
  func markComplete(_ episodeID: Episode.ID) async throws -> Bool {
    log.debug("markComplete: \(episodeID)")

    return try await appDB.db.write { db in
      try Episode
        .withID(episodeID)
        .updateAll(
          db,
          Episode.Columns.completionDate.set(to: Date()),
          Episode.Columns.currentTime.set(to: 0)
        )
    } > 0
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
        .withIDs(podcastIDs)
        .updateAll(db, Podcast.Columns.subscribed.set(to: subscribed))
    }
  }
}
