// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Tagged

extension Container {
  internal func makeRepo() -> Repo { Repo(self.appDB()) }
  var repo: Factory<any Databasing> {
    Factory(self) { self.makeRepo() }.scope(.cached)
  }
}

struct Repo: Databasing, Sendable {
  @DynamicInjected(\.queue) private var queue

  private static let log = Log.as(LogSubsystem.Database.repo)

  // MARK: - Initialization

  var db: any DatabaseReader { appDB.db }
  private let appDB: AppDB
  fileprivate init(_ appDB: AppDB) {
    self.appDB = appDB
  }

  // MARK: - Global Readers

  func allPodcasts(_ filter: SQLExpression) async throws -> [Podcast] {
    let request = Podcast.all().filter(filter)
    return try await appDB.db.read { db in
      try request.fetchAll(db)
    }
  }

  func allPodcastSeries(_ filter: SQLExpression) async throws(RepoError)
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

  func podcastSeries(_ feedURLs: [FeedURL]) async throws -> IdentifiedArray<FeedURL, PodcastSeries>
  {
    try await appDB.db.read { db in
      try Podcast
        .filter { feedURLs.contains($0.feedURL) }
        .including(all: Podcast.episodes)
        .asRequest(of: PodcastSeries.self)
        .fetchIdentifiedArray(db, id: \.podcast.feedURL)
    }
  }

  func podcastSeries(_ feedURL: FeedURL) async throws -> PodcastSeries? {
    try await podcastSeries([feedURL]).first
  }

  // MARK: - Episode Readers

  func episode(_ episodeID: Episode.ID) async throws -> Episode? {
    try await appDB.db.read { db in
      try Episode
        .withID(episodeID)
        .fetchOne(db)
    }
  }

  func podcastEpisode(_ episodeID: Episode.ID) async throws -> PodcastEpisode? {
    try await appDB.db.read { db in
      try Episode
        .withID(episodeID)
        .including(required: Episode.podcast)
        .asRequest(of: PodcastEpisode.self)
        .fetchOne(db)
    }
  }

  func latestEpisode(for podcastID: Podcast.ID) async throws -> Episode? {
    try await appDB.db.read { db in
      try Episode
        .filter(Episode.Columns.podcastId == podcastID)
        .order(Episode.Columns.pubDate.desc)
        .fetchOne(db)
    }
  }

  // MARK: - Series Writers

  @discardableResult
  func insertSeries(_ unsavedPodcast: UnsavedPodcast, unsavedEpisodes: [UnsavedEpisode])
    async throws(RepoError) -> PodcastSeries
  {
    Self.log.debug(
      """
      Inserting series
        Podcast: \(unsavedPodcast.toString)
        \(unsavedEpisodes.count) episodes
      """
    )

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

  func updateSeriesFromFeed(
    podcastID: Podcast.ID,
    podcast: Podcast?,
    unsavedEpisodes: [UnsavedEpisode],
    existingEpisodes: [Episode]
  ) async throws(RepoError) {
    do {
      try await appDB.db.write { db in
        // Update only RSS feed attributes for podcast if provided
        if let podcast = podcast {
          try Podcast
            .withID(podcast.id)
            .updateAll(db, podcast.rssColumnAssignments())
        }

        // Update only RSS feed attributes for existing episodes (excluding duration)
        for existingEpisode in existingEpisodes {
          try Episode
            .withID(existingEpisode.id)
            .updateAll(db, existingEpisode.rssColumnAssignments())
        }

        // Insert new episodes (all attributes needed for new episodes)
        for var unsavedEpisode in unsavedEpisodes {
          unsavedEpisode.podcastId = podcastID
          try unsavedEpisode.insert(db)
        }
      }
    } catch {
      let description =
        podcast?.toString
        ?? (!existingEpisodes.isEmpty
          ? "Episodes: \(existingEpisodes.map(\.toString).joined(separator: ", "))"
          : "UnsavedEpisodes: \(unsavedEpisodes.map(\.toString).joined(separator: ", "))")
      throw RepoError.updateFailure(
        type: PodcastSeries.self,
        id: podcastID.rawValue,
        description: description,
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
    Self.log.trace("updateCurrentTime: \(episodeID) to \(currentTime)")

    return try await appDB.db.write { db in
      try Episode
        .withID(episodeID)
        .updateAll(db, Episode.Columns.currentTime.set(to: currentTime))
    } > 0
  }

  @discardableResult
  func updateCachedFilename(_ episodeID: Episode.ID, _ cachedFilename: String?) async throws -> Bool
  {
    Self.log.debug("updateCachedFilename: \(episodeID) to \(cachedFilename ?? "nil")")

    return try await appDB.db.write { db in
      try Episode
        .withID(episodeID)
        .updateAll(db, Episode.Columns.cachedFilename.set(to: cachedFilename))
    } > 0
  }

  @discardableResult
  func markComplete(_ episodeID: Episode.ID) async throws -> Bool {
    Self.log.debug("markComplete: \(episodeID)")

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

  @discardableResult
  func updateLastUpdate(_ podcastID: Podcast.ID) async throws -> Bool {
    Self.log.trace("updateLastUpdate: \(podcastID)")

    return try await appDB.db.write { db in
      try Podcast
        .withID(podcastID)
        .updateAll(db, Podcast.Columns.lastUpdate.set(to: Date()))
    } > 0
  }

  // MARK: Private Helpers

  private func _setSubscribedColumn(_ podcastIDs: [Podcast.ID], to subscribed: Bool) async throws
    -> Int
  {
    try await appDB.db.write { db in
      try Podcast
        .withIDs(podcastIDs)
        .updateAll(db, Podcast.Columns.subscriptionDate.set(to: subscribed ? Date() : nil))
    }
  }
}
