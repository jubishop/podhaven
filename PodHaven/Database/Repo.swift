// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging
import Tagged

extension Container {
  internal func makeRepo() -> Repo { Repo(self.appDB()) }
  var repo: Factory<any Databasing> {
    Factory(self) { self.makeRepo() }.scope(.cached)
  }

}

struct Repo: Databasing, Sendable {
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.playManager) private var playManager

  private var fileManager: any FileManaging { Container.shared.fileManager() }
  private var sharedState: SharedState { Container.shared.sharedState() }

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

  func allPodcastSeries(
    _ filter: SQLExpression,
    order: SQLOrdering,
    limit: Int
  ) async throws(RepoError)
    -> [PodcastSeries]
  {
    do {
      return try await appDB.db.read { db in
        try Podcast
          .all()
          .filter(filter)
          .order(order)
          .limit(limit)
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

  func episode(_ episodeID: Episode.ID) async throws -> Episode? {
    try await appDB.db.read { db in
      try Episode
        .withID(episodeID)
        .fetchOne(db)
    }
  }

  func episode(_ mediaGUID: MediaGUID) async throws -> Episode? {
    try await appDB.db.read { db in
      try Episode
        .filter { $0.guid == mediaGUID.guid && $0.mediaURL == mediaGUID.mediaURL }
        .fetchOne(db)
    }
  }

  func episodes(_ downloadTaskIDs: [URLSessionDownloadTask.ID]) async throws -> [Episode] {
    guard !downloadTaskIDs.isEmpty else { return [] }
    return try await appDB.db.read { db in
      try Episode
        .filter(downloadTaskIDs.contains(Episode.Columns.downloadTaskID))
        .fetchAll(db)
    }
  }

  func episode(_ downloadTaskID: URLSessionDownloadTask.ID) async throws -> Episode? {
    try await episodes([downloadTaskID]).first
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

  func podcastEpisode(_ mediaGUID: MediaGUID) async throws -> PodcastEpisode? {
    try await appDB.db.read { db in
      try Episode
        .filter { $0.guid == mediaGUID.guid && $0.mediaURL == mediaGUID.mediaURL }
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

  func cachedEpisodes() async throws -> [Episode] {
    try await appDB.db.read { db in
      try Episode
        .all()
        .cached()
        .fetchAll(db)
    }
  }

  // MARK: - Series Writers

  @discardableResult
  func insertSeries(_ unsavedPodcastSeries: UnsavedPodcastSeries) async throws(RepoError)
    -> PodcastSeries
  {
    Self.log.debug(
      """
      Inserting series
        Podcast: \(unsavedPodcastSeries.toString)
        \(unsavedPodcastSeries.unsavedEpisodes.count) episodes
      """
    )

    do {
      return try await appDB.db.write { db in
        let unsavedPodcast = unsavedPodcastSeries.unsavedPodcast
        let podcast = try unsavedPodcast.insertAndFetch(db, as: Podcast.self)
        var episodes = IdentifiedArrayOf<Episode>()
        for var unsavedEpisode in unsavedPodcastSeries.unsavedEpisodes {
          unsavedEpisode.podcastId = podcast.id
          episodes.append(try unsavedEpisode.insertAndFetch(db, as: Episode.self))
        }
        return PodcastSeries(podcast: podcast, episodes: episodes)
      }
    } catch let error as DatabaseError
      where error.extendedResultCode == .SQLITE_CONSTRAINT_UNIQUE
    {
      throw RepoError.duplicateConflict(
        unsavedPodcastSeries: unsavedPodcastSeries,
        caught: error
      )
    } catch {
      throw RepoError.insertFailure(
        type: PodcastSeries.self,
        description: "PodcastSeries: \(unsavedPodcastSeries.toString)",
        caught: error
      )
    }
  }

  @discardableResult
  func updateSeriesFromFeed(
    podcastSeries: PodcastSeries,
    podcast: Podcast?,
    unsavedEpisodes: [UnsavedEpisode],
    existingEpisodes: [Episode]
  ) async throws(RepoError) -> [Episode] {
    do {
      return try await appDB.db.write { db in
        var newEpisodes = [Episode](capacity: unsavedEpisodes.count)

        // Update only RSS feed attributes for podcast if provided
        if let podcast = podcast {
          try Podcast
            .withID(podcast.id)
            .updateAll(db, podcast.rssColumnAssignments)
        }

        // Update only RSS feed attributes for existing episodes (excluding duration)
        for existingEpisode in existingEpisodes {
          try Episode
            .withID(existingEpisode.id)
            .updateAll(db, existingEpisode.rssColumnAssignments)
        }

        // Insert new episodes (all attributes needed for new episodes)
        for var unsavedEpisode in unsavedEpisodes {
          unsavedEpisode.podcastId = podcastSeries.id
          newEpisodes.append(try unsavedEpisode.insertAndFetch(db, as: Episode.self))
        }

        if podcastSeries.podcast.queueAllEpisodes == .onTop {
          try queue.unshift(db, newEpisodes.map(\.id))
        } else if podcastSeries.podcast.queueAllEpisodes == .onBottom {
          try queue.append(db, newEpisodes.map(\.id))
        }
        return newEpisodes
      }
    } catch {
      var description = podcastSeries.toString
      if !existingEpisodes.isEmpty {
        description +=
          "\nEpisodes:\n    \(existingEpisodes.map(\.toString).joined(separator: "\n    "))"
      }
      if !unsavedEpisodes.isEmpty {
        description +=
          "\nUnsavedEpisodes:\n    \(unsavedEpisodes.map(\.toString).joined(separator: "\n    "))"
      }
      throw RepoError.updateFailure(
        type: PodcastSeries.self,
        id: podcastSeries.id.rawValue,
        description: description,
        caught: error
      )
    }
  }

  // MARK: - Podcast Writers

  @discardableResult
  func deletePodcast(_ podcastIDs: [Podcast.ID]) async throws -> Int {
    let episodesToDelete = try await appDB.db.read { db in
      try Episode.all()
        .filter { podcastIDs.contains($0.podcastId) }
        .fetchAll(db)
    }

    for episode in episodesToDelete {
      // Remove cached episode files
      if let url = episode.cachedURL {
        do {
          try fileManager.removeItem(at: url.rawValue)
          Self.log.debug("Removed cached file at: \(url)")
        } catch {
          Self.log.error(error)
        }
      }

      // Stop playback if needed
      if sharedState.onDeck?.id == episode.id {
        await playManager.stop()
        Self.log.debug("Stopped playback for \(episode.toString) because its being deleted")
      }
    }

    return try await appDB.db.write { db in
      // Remove episodes from queue
      let queuedEpisodeIDs =
        try Episode.all()
        .queued()
        .filter { podcastIDs.contains($0.podcastId) }
        .selectID()
        .fetchAll(db)
      try queue.dequeue(db, queuedEpisodeIDs)

      // Finally delete the podcast (cascades to episodes)
      return try Podcast.withIDs(podcastIDs).deleteAll(db)
    }
  }

  @discardableResult
  func deletePodcast(_ podcastID: Podcast.ID) async throws -> Bool {
    try await deletePodcast([podcastID]) > 0
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
            let unsavedPodcast = unsavedPodcastEpisode.unsavedPodcast
            podcast = try unsavedPodcast.upsertLimitedColumns(
              db,
              columns: unsavedPodcast.rssUpdatableColumns.map(\.0)
            )
            upsertedPodcasts.append(podcast)
          }

          var newUnsavedEpisode = unsavedPodcastEpisode.unsavedEpisode
          newUnsavedEpisode.podcastId = podcast.id
          let episode: Episode = try newUnsavedEpisode.upsertLimitedColumns(
            db,
            columns: newUnsavedEpisode.rssUpdatableColumns.map(\.0)
          )
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

  // MARK: - Podcast Attribute Writers

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

  @discardableResult
  func updateDefaultPlaybackRate(_ podcastID: Podcast.ID, defaultPlaybackRate: Double?) async throws
    -> Bool
  {
    Self.log.debug(
      "updateDefaultPlaybackRate: \(podcastID) to \(String(describing: defaultPlaybackRate))"
    )

    return try await appDB.db.write { db in
      try Podcast
        .withID(podcastID)
        .updateAll(db, Podcast.Columns.defaultPlaybackRate.set(to: defaultPlaybackRate))
    } > 0
  }

  @discardableResult
  func updateQueueAllEpisodes(_ podcastID: Podcast.ID, queueAllEpisodes: QueueAllEpisodes)
    async throws -> Bool
  {
    Self.log.debug("updateQueueAllEpisodes: \(podcastID) to \(queueAllEpisodes)")

    return try await appDB.db.write { db in
      try Podcast
        .withID(podcastID)
        .updateAll(db, Podcast.Columns.queueAllEpisodes.set(to: queueAllEpisodes))
    } > 0
  }

  @discardableResult
  func updateCacheAllEpisodes(_ podcastID: Podcast.ID, cacheAllEpisodes: CacheAllEpisodes)
    async throws -> Bool
  {
    Self.log.debug("updateCacheAllEpisodes: \(podcastID) to \(cacheAllEpisodes)")

    return try await appDB.db.write { db in
      try Podcast
        .withID(podcastID)
        .updateAll(db, Podcast.Columns.cacheAllEpisodes.set(to: cacheAllEpisodes))
    } > 0
  }

  @discardableResult
  func updateNotifyNewEpisodes(_ podcastID: Podcast.ID, notifyNewEpisodes: Bool)
    async throws -> Bool
  {
    Self.log.debug("updateNotifyNewEpisodes: \(podcastID) to \(notifyNewEpisodes)")

    return try await appDB.db.write { db in
      try Podcast
        .withID(podcastID)
        .updateAll(db, Podcast.Columns.notifyNewEpisodes.set(to: notifyNewEpisodes))
    } > 0
  }

  // MARK: - Episode Attribute Writers

  @discardableResult
  func updateDuration(_ episodeID: Episode.ID, duration: CMTime) async throws -> Bool {
    Self.log.debug("updateDuration: \(episodeID) to \(duration)")

    return try await appDB.db.write { db in
      try Episode
        .withID(episodeID)
        .updateAll(db, Episode.Columns.duration.set(to: duration))
    } > 0
  }

  @discardableResult
  func updateCurrentTime(_ episodeID: Episode.ID, currentTime: CMTime) async throws -> Bool {
    Self.log.trace("updateCurrentTime: \(episodeID) to \(currentTime)")

    return try await appDB.db.write { db in
      try Episode
        .withID(episodeID)
        .updateAll(db, Episode.Columns.currentTime.set(to: currentTime))
    } > 0
  }

  @discardableResult
  func updateDownloadTaskID(_ episodeID: Episode.ID, downloadTaskID: URLSessionDownloadTask.ID?)
    async throws
    -> Bool
  {
    Self.log.debug("updateDownloadTaskID: \(episodeID) to \(String(describing: downloadTaskID))")

    return try await appDB.db.write { db in
      try Episode
        .withID(episodeID)
        .updateAll(db, Episode.Columns.downloadTaskID.set(to: downloadTaskID))
    } > 0
  }

  @discardableResult
  func updateCachedFilename(_ episodeID: Episode.ID, cachedFilename: String?) async throws -> Bool {
    Self.log.debug("updateCachedFilename: \(episodeID) to \(cachedFilename ?? "nil")")

    return try await appDB.db.write { db in
      try Episode
        .withID(episodeID)
        .updateAll(db, Episode.Columns.cachedFilename.set(to: cachedFilename))
    } > 0
  }

  @discardableResult
  func updateSaveInCache(_ episodeID: Episode.ID, saveInCache: Bool) async throws -> Bool {
    Self.log.debug("updateSaveInCache: \(episodeID) to \(saveInCache)")

    return try await appDB.db.write { db in
      try Episode
        .withID(episodeID)
        .updateAll(db, Episode.Columns.saveInCache.set(to: saveInCache))
    } > 0
  }

  @discardableResult
  func markFinished(_ episodeIDs: [Episode.ID]) async throws -> Int {
    Self.log.debug("markFinished: \(episodeIDs)")

    guard !episodeIDs.isEmpty else { return 0 }

    return try await appDB.db.write { db in
      try Episode
        .withIDs(episodeIDs)
        .updateAll(
          db,
          Episode.Columns.finishDate.set(to: Date()),
          Episode.Columns.currentTime.set(to: 0)
        )
    }
  }

  @discardableResult
  func markFinished(_ episodeID: Episode.ID) async throws -> Bool {
    try await markFinished([episodeID]) > 0
  }

  // MARK: Private Helpers

  private func _setSubscribedColumn(_ podcastIDs: [Podcast.ID], to subscribed: Bool) async throws
    -> Int
  {
    Self.log.debug("Set \(podcastIDs) to: \(subscribed ? "subscribed" : "unsubscribed")")

    guard !podcastIDs.isEmpty else { return 0 }

    return try await appDB.db.write { db in
      try Podcast
        .withIDs(podcastIDs)
        .updateAll(db, Podcast.Columns.subscriptionDate.set(to: subscribed ? Date() : nil))
    }
  }
}
