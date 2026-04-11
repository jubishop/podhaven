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
    limit: Int,
    includeTags: Bool
  ) async throws
    -> [PodcastSeries]
  {
    try await appDB.db.read { db in
      var baseRequest =
        Podcast
        .all()
        .filter(filter)
        .order(order)
        .limit(limit)
        .including(all: Podcast.episodes)

      if includeTags {
        baseRequest = baseRequest.including(
          all: Podcast.tags.order { $0.name.collating(.nocase) }
        )
      }

      return
        try baseRequest
        .asRequest(of: PodcastSeries.self)
        .fetchAll(db)
    }
  }

  // MARK: - Series Readers

  func podcastSeries(_ podcastID: Podcast.ID) async throws -> PodcastSeries? {
    try await appDB.db.read { db in
      try Podcast
        .withID(podcastID)
        .including(all: Podcast.episodes)
        .including(all: Podcast.tags.order { $0.name.collating(.nocase) })
        .asRequest(of: PodcastSeries.self)
        .fetchOne(db)
    }
  }

  func podcastSeries(_ feedURL: FeedURL, iTunesID: ITunesPodcastID? = nil) async throws
    -> PodcastSeries?
  {
    try await appDB.db.read { db in
      let base =
        Podcast
        .including(all: Podcast.episodes)
        .including(all: Podcast.tags.order { $0.name.collating(.nocase) })
        .asRequest(of: PodcastSeries.self)
      // feedURL takes priority over iTunesID
      if let result = try base.filter(Podcast.Columns.feedURL == feedURL).fetchOne(db) {
        return result
      }
      if let iTunesID {
        return try base.filter(Podcast.Columns.iTunesID == iTunesID).fetchOne(db)
      }
      return nil
    }
  }

  // MARK: - Podcast Readers

  func podcast(_ podcastID: Podcast.ID) async throws -> Podcast? {
    try await appDB.db.read { db in
      try Podcast
        .withID(podcastID)
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

  func podcastEpisodes(_ episodeIDs: [Episode.ID]) async throws -> [PodcastEpisode] {
    guard !episodeIDs.isEmpty else { return [] }
    return try await appDB.db.read { db in
      try Episode
        .filter(episodeIDs.contains(Episode.Columns.id))
        .including(required: Episode.podcast)
        .asRequest(of: PodcastEpisode.self)
        .fetchAll(db)
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
  func insertSeries(_ unsavedPodcastSeries: UnsavedPodcastSeries) async throws
    -> PodcastSeries
  {
    Self.log.debug(
      """
      Inserting series
        Podcast: \(unsavedPodcastSeries.toString)
        \(unsavedPodcastSeries.unsavedEpisodes.count) episodes
      """
    )

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
  }

  @discardableResult
  func updateSeriesFromFeed(
    podcastSeries: PodcastSeries,
    podcast: Podcast?,
    unsavedEpisodes: [UnsavedEpisode],
    existingEpisodes: [Episode]
  ) async throws -> [Episode] {
    try await appDB.db.write { db in
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
          Self.log.caughtError(
            "Failed to remove cached file at \(url) for episode \(episode.toString)",
            error
          )
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

  // MARK: - Tag Writers

  @discardableResult
  func insertTag(_ unsavedTag: UnsavedTag) async throws -> Tag {
    try await appDB.db.write { db in
      try unsavedTag.insertAndFetch(db, as: Tag.self)
    }
  }

  @discardableResult
  func renameTag(_ tagID: Tag.ID, newName: String) async throws -> Bool {
    let normalizedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedName.isEmpty else {
      throw DatabaseError(message: "Tag name cannot be empty")
    }

    return try await appDB.db.write { db in
      try Tag
        .withID(tagID)
        .updateAll(db, Tag.Columns.name.set(to: normalizedName))
    } > 0
  }

  @discardableResult
  func deleteTag(_ tagID: Tag.ID) async throws -> Bool {
    try await appDB.db.write { db in
      try Tag
        .withID(tagID)
        .deleteAll(db)
    } > 0
  }

  func addTag(_ tagID: Tag.ID, to podcastID: Podcast.ID) async throws {
    try await appDB.db.write { db in
      try PodcastTag(podcastId: podcastID, tagId: tagID).insert(db)
    }
  }

  @discardableResult
  func removeTag(_ tagID: Tag.ID, from podcastID: Podcast.ID) async throws -> Bool {
    try await appDB.db.write { db in
      try PodcastTag
        .filter(
          PodcastTag.Columns.podcastId == podcastID
            && PodcastTag.Columns.tagId == tagID
        )
        .deleteAll(db)
    } > 0
  }

  func addTag(_ tagID: Tag.ID, to episodeID: Episode.ID) async throws {
    try await appDB.db.write { db in
      try EpisodeTag(episodeId: episodeID, tagId: tagID).insert(db)
    }
  }

  @discardableResult
  func removeTag(_ tagID: Tag.ID, from episodeID: Episode.ID) async throws -> Bool {
    try await appDB.db.write { db in
      try EpisodeTag
        .filter(
          EpisodeTag.Columns.episodeId == episodeID
            && EpisodeTag.Columns.tagId == tagID
        )
        .deleteAll(db)
    } > 0
  }

  // MARK: - Recommendation Readers

  func allSignalEpisodes() async throws -> [Episode] {
    try await appDB.db.read { db in
      try Episode
        .filter(Episode.rated || Episode.finished)
        .fetchAll(db)
    }
  }

  func allCandidateEpisodes(excluding excludedIDs: [Episode.ID] = []) async throws -> [Episode] {
    try await appDB.db.read { db in
      var request =
        Episode
        .filter(Episode.unstarted)
        .filter(Episode.unfinished)
        .filter(!Episode.rated)
        .filter(Episode.unqueued)

      if !excludedIDs.isEmpty {
        request = request.filter(!excludedIDs.contains(Episode.Columns.id))
      }

      return try request.fetchAll(db)
    }
  }

  func allPodcastTags() async throws -> [PodcastTag] {
    try await appDB.db.read { db in
      try PodcastTag.fetchAll(db)
    }
  }

  // MARK: - Embedding Writers

  @discardableResult
  func upsertEmbedding(_ unsaved: UnsavedEpisodeEmbedding) async throws -> EpisodeEmbedding {
    Self.log.debug("upsertEmbedding: episode \(unsaved.episodeId)")
    return try await appDB.db.write { db in
      try unsaved.upsertAndFetch(db, as: EpisodeEmbedding.self)
    }
  }

  @discardableResult
  func upsertPodcastEmbedding(_ unsaved: UnsavedPodcastEmbedding) async throws -> PodcastEmbedding {
    Self.log.debug("upsertPodcastEmbedding: podcast \(unsaved.podcastId)")
    return try await appDB.db.write { db in
      try unsaved.upsertAndFetch(db, as: PodcastEmbedding.self)
    }
  }

  // MARK: - Embedding Readers

  func hasEmbeddings() async throws -> Bool {
    try await appDB.db.read { db in
      try EpisodeEmbedding.fetchCount(db) > 0
    }
  }

  func embedding(for episodeID: Episode.ID) async throws -> EpisodeEmbedding? {
    try await appDB.db.read { db in
      try EpisodeEmbedding
        .filter(EpisodeEmbedding.Columns.episodeId == episodeID)
        .fetchOne(db)
    }
  }

  func embeddings(for episodeIDs: [Episode.ID]) async throws
    -> IdentifiedArray<Episode.ID, EpisodeEmbedding>
  {
    guard !episodeIDs.isEmpty else { return IdentifiedArray(id: \.episodeId) }
    return try await appDB.db.read { db in
      try EpisodeEmbedding
        .filter(episodeIDs.contains(EpisodeEmbedding.Columns.episodeId))
        .fetchIdentifiedArray(db, id: \.episodeId)
    }
  }

  func podcastEmbedding(for podcastID: Podcast.ID) async throws -> PodcastEmbedding? {
    try await appDB.db.read { db in
      try PodcastEmbedding
        .filter(PodcastEmbedding.Columns.podcastId == podcastID)
        .fetchOne(db)
    }
  }

  func podcastEmbeddings(for podcastIDs: [Podcast.ID]) async throws -> [PodcastEmbedding] {
    guard !podcastIDs.isEmpty else { return [] }
    return try await appDB.db.read { db in
      try PodcastEmbedding
        .filter(podcastIDs.contains(PodcastEmbedding.Columns.podcastId))
        .fetchAll(db)
    }
  }

  func podcasts(for podcastIDs: [Podcast.ID]) async throws -> IdentifiedArrayOf<Podcast> {
    guard !podcastIDs.isEmpty else { return [] }
    return try await appDB.db.read { db in
      try Podcast
        .filter(podcastIDs.contains(Podcast.Columns.id))
        .fetchIdentifiedArray(db)
    }
  }

  func episodesNeedingEmbeddings(revision: Int) async throws -> [Episode] {
    try await appDB.db.read { db in
      let embeddingAlias = TableAlias()
      let podcastAlias = TableAlias()

      return
        try Episode
        .joining(required: Episode.podcast.aliased(podcastAlias))
        .joining(optional: Episode.embedding.aliased(embeddingAlias))
        .filter(
          Episode.rated || Episode.finished
            || (Episode.unstarted && Episode.unfinished && !Episode.rated && Episode.unqueued)
        )
        .filter(
          embeddingAlias[EpisodeEmbedding.Columns.id] == nil
            || embeddingAlias[EpisodeEmbedding.Columns.embeddingRevision] != revision
            || Episode.Columns.contentUpdatedAt
              > embeddingAlias[EpisodeEmbedding.Columns.creationDate]
            || podcastAlias[Podcast.Columns.contentUpdatedAt]
              > embeddingAlias[EpisodeEmbedding.Columns.creationDate]
        )
        .order(
          SQL(
            """
            CASE WHEN \(Episode.Columns.rating) IS NOT NULL \
            OR \(Episode.Columns.finishDate) IS NOT NULL THEN 0 ELSE 1 END
            """
          )
        )
        .fetchAll(db)
    }
  }

  // MARK: - Episode Writers

  @discardableResult
  func upsertPodcastEpisodes(_ unsavedPodcastEpisodes: [UnsavedPodcastEpisode])
    async throws -> [PodcastEpisode]
  {
    guard !unsavedPodcastEpisodes.isEmpty
    else { return [] }

    return try await appDB.db.write { db in
      var upsertedPodcastsByFeedURL: IdentifiedArray<FeedURL, Podcast> =
        IdentifiedArray(id: \.feedURL)
      var upsertedPodcastsByITunesID: IdentifiedArray<ITunesPodcastID?, Podcast> =
        IdentifiedArray(id: \.iTunesID)

      return try unsavedPodcastEpisodes.map { unsavedPodcastEpisode in
        let podcast: Podcast
        let unsavedPodcast = unsavedPodcastEpisode.unsavedPodcast

        if let cached = upsertedPodcastsByFeedURL[id: unsavedPodcast.feedURL] {
          podcast = cached
        } else if let iTunesID = unsavedPodcast.iTunesID,
          let cached = upsertedPodcastsByITunesID[id: iTunesID]
        {
          podcast = cached
        } else if let iTunesID = unsavedPodcast.iTunesID,
          let existing =
            try Podcast
            .filter(Podcast.Columns.iTunesID == iTunesID).fetchOne(db)
        {
          podcast = existing
        } else {
          podcast = try unsavedPodcast.upsertAndFetch(
            db,
            as: Podcast.self,
            updating: .noColumnUnlessSpecified,
            doUpdate: unsavedPodcast.rssUpsertAssignments
          )
        }

        upsertedPodcastsByFeedURL.append(podcast)
        if podcast.iTunesID != nil {
          upsertedPodcastsByITunesID.append(podcast)
        }

        var newUnsavedEpisode = unsavedPodcastEpisode.unsavedEpisode
        newUnsavedEpisode.podcastId = podcast.id
        let episode: Episode = try newUnsavedEpisode.upsertAndFetch(
          db,
          as: Episode.self,
          updating: .noColumnUnlessSpecified,
          doUpdate: newUnsavedEpisode.rssUpsertAssignments
        )
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
  func updateITunesID(_ podcastID: Podcast.ID, iTunesID: ITunesPodcastID) async throws -> Bool {
    Self.log.debug("updateITunesID: \(podcastID) to \(iTunesID)")

    return try await appDB.db.write { db in
      try Podcast
        .withID(podcastID)
        .updateAll(db, Podcast.Columns.iTunesID.set(to: iTunesID))
    } > 0
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
  func updateRating(_ episodeID: Episode.ID, rating: EpisodeRating?) async throws -> Bool {
    Self.log.debug("updateRating: \(episodeID) to \(String(describing: rating))")

    return try await appDB.db.write { db in
      try Episode
        .withID(episodeID)
        .updateAll(
          db,
          Episode.Columns.rating.set(to: rating),
          Episode.Columns.ratingDate.set(to: rating != nil ? Date() : nil)
        )
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
