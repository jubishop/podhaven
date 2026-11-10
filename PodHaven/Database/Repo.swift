// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging
import Tagged

extension Container {
  var repo: Factory<any Databasing> {
    Factory(self) { self.makeRepo() }.scope(.cached)
  }
}

struct Repo: Databasing {
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.publisherTranscriptProcessor) private var publisherTranscriptProcessor
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.transcriptionProcessor) private var transcriptionProcessor

  private var cacheFileStore: CacheFileStore { Container.shared.cacheFileStore() }

  private static let log = Log.as(LogSubsystem.Database.repo)

  // MARK: - Initialization

  var db: AppDB.Reader { reader }
  private let reader: AppDB.Reader
  let writer: AppDB.Writer
  init(reader: AppDB.Reader, writer: AppDB.Writer) {
    self.reader = reader
    self.writer = writer
  }

  // MARK: - Global Readers

  func allPodcasts(_ filter: SQLExpression) async throws -> [Podcast] {
    let request = Podcast.all().filter(filter)
    return try await reader.read { db in
      try request.fetchAll(db)
    }
  }

  func allPodcasts(
    _ filter: SQLExpression,
    order: [SQLOrdering],
    limit: Int
  ) async throws -> [Podcast] {
    try await reader.read { db in
      try Podcast
        .all()
        .filter(filter)
        .order(order)
        .limit(limit)
        .fetchAll(db)
    }
  }

  // MARK: - Series Readers

  func podcast(_ podcastID: Podcast.ID) async throws -> Podcast? {
    try await reader.read { db in
      try Podcast.withID(podcastID).fetchOne(db)
    }
  }

  func podcastSeries(_ podcastID: Podcast.ID) async throws -> PodcastSeries? {
    try await reader.read { db in
      try Podcast
        .withID(podcastID)
        .including(all: Podcast.episodes)
        .asRequest(of: PodcastSeries.self)
        .fetchOne(db)
    }
  }

  func podcastSeries(_ feedURL: FeedURL, iTunesID: ITunesPodcastID? = nil) async throws
    -> PodcastSeries?
  {
    try await reader.read { db in
      let base =
        Podcast
        .including(all: Podcast.episodes)
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

  // MARK: - Series Detail Readers

  func podcastSeriesDetail(_ podcastID: Podcast.ID) async throws -> PodcastSeriesDetail? {
    try await reader.read { db in
      try PodcastSeriesDetail.fetchOne(podcastID, in: db)
    }
  }

  func podcastSeriesDetail(_ feedURL: FeedURL, iTunesID: ITunesPodcastID? = nil) async throws
    -> PodcastSeriesDetail?
  {
    try await reader.read { db in
      // feedURL takes priority over iTunesID
      if let byFeed = try Podcast.filter(Podcast.Columns.feedURL == feedURL).fetchOne(db) {
        return try PodcastSeriesDetail.fetchOne(podcast: byFeed, in: db)
      }
      if let iTunesID,
        let byITunes = try Podcast.filter(Podcast.Columns.iTunesID == iTunesID).fetchOne(db)
      {
        return try PodcastSeriesDetail.fetchOne(podcast: byITunes, in: db)
      }
      return nil
    }
  }

  // MARK: - Episode Readers

  func episode(_ episodeID: Episode.ID) async throws -> Episode? {
    try await reader.read { db in
      try Episode
        .withID(episodeID)
        .fetchOne(db)
    }
  }

  func transcriptionCheckpoint(_ episodeID: Episode.ID) async throws
    -> TranscriptionCheckpoint?
  {
    try await reader.read { db in
      guard
        let stored =
          try EpisodeTranscriptionCheckpoint
          .filter(EpisodeTranscriptionCheckpoint.Columns.episodeId == episodeID)
          .fetchOne(db)
      else {
        return nil
      }
      return try stored.checkpoint()
    }
  }

  func episodesMatching(
    podcastID: Podcast.ID,
    guids: [GUID],
    mediaURLs: [MediaURL]
  ) async throws -> [Episode] {
    guard !guids.isEmpty || !mediaURLs.isEmpty else { return [] }
    return try await reader.read { db in
      var filter: SQLExpression = Episode.Columns.podcastId == podcastID
      if !guids.isEmpty, !mediaURLs.isEmpty {
        filter =
          filter
          && (guids.contains(Episode.Columns.guid)
            || mediaURLs.contains(Episode.Columns.mediaURL))
      } else if !guids.isEmpty {
        filter = filter && guids.contains(Episode.Columns.guid)
      } else {
        filter = filter && mediaURLs.contains(Episode.Columns.mediaURL)
      }
      return try Episode.filter(filter).fetchAll(db)
    }
  }

  func feedMergeEpisodes(
    podcastID: Podcast.ID,
    matching mediaGUIDs: [MediaGUID]
  ) async throws -> [FeedMergeEpisode] {
    guard !mediaGUIDs.isEmpty else { return [] }
    let guids = mediaGUIDs.map(\.guid)
    let mediaURLs = mediaGUIDs.map(\.mediaURL)
    return try await reader.read { db in
      try FeedMergeEpisode
        .filter(
          Episode.Columns.podcastId == podcastID
            && (guids.contains(Episode.Columns.guid)
              || mediaURLs.contains(Episode.Columns.mediaURL))
        )
        .fetchAll(db)
    }
  }

  func podcastEpisode(_ episodeID: Episode.ID) async throws -> PodcastEpisode? {
    try await reader.read { db in
      try Episode
        .withID(episodeID)
        .including(required: Episode.podcast)
        .asRequest(of: PodcastEpisode.self)
        .fetchOne(db)
    }
  }

  func podcastEpisodes(_ episodeIDs: [Episode.ID]) async throws -> [PodcastEpisode] {
    guard !episodeIDs.isEmpty else { return [] }
    let fetched: [PodcastEpisode] = try await reader.read { db in
      try Episode
        .filter(episodeIDs.contains(Episode.Columns.id))
        .including(required: Episode.podcast)
        .asRequest(of: PodcastEpisode.self)
        .fetchAll(db)
    }
    // Preserves the order as passed in.
    let byID = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
    return episodeIDs.compactMap { byID[$0] }
  }

  func podcastEpisode(
    _ mediaGUID: MediaGUID,
    feedURL: FeedURL
  ) async throws -> PodcastEpisode? {
    try await reader.read { db in
      try Episode
        .filter { $0.guid == mediaGUID.guid && $0.mediaURL == mediaGUID.mediaURL }
        .including(required: Episode.podcast.filter(Podcast.Columns.feedURL == feedURL))
        .asRequest(of: PodcastEpisode.self)
        .fetchOne(db)
    }
  }

  func latestEpisode(for podcastID: Podcast.ID) async throws -> Episode? {
    try await reader.read { db in
      try Episode
        .filter(Episode.Columns.podcastId == podcastID)
        .order(Episode.Columns.pubDate.desc)
        .fetchOne(db)
    }
  }

  func cachedEpisodes() async throws -> [Episode] {
    try await reader.read { db in
      try Episode
        .all()
        .cached()
        .fetchAll(db)
    }
  }

  func downloadingEpisodeIDs() async throws -> [Episode.ID] {
    try await reader.read { db in
      try Episode
        .filter(Episode.Columns.downloading == true)
        .select(Episode.Columns.id, as: Episode.ID.self)
        .fetchAll(db)
    }
  }

  func queuedEpisodeIDs() async throws -> [Episode.ID] {
    try await reader.read { db in
      try Episode.all()
        .queued()
        .select(Episode.Columns.id, as: Episode.ID.self)
        .fetchAll(db)
    }
  }

  // MARK: - Series Writers

  @discardableResult
  func insertSeries(_ unsavedPodcastSeries: UnsavedPodcastSeries, level: Logger.Level)
    async throws -> PodcastSeries
  {
    Self.log.log(
      level: level,
      """
      Inserting series
        Podcast: \(unsavedPodcastSeries.toString)
        \(unsavedPodcastSeries.unsavedEpisodes.count) episodes
      """
    )

    return try await writer.write(level: level) { db in
      let unsavedPodcast = unsavedPodcastSeries.unsavedPodcast
      let podcast = try unsavedPodcast.insertAndFetch(db, as: Podcast.self)
      var episodes = IdentifiedArrayOf<Episode>()
      for var unsavedEpisode in unsavedPodcastSeries.unsavedEpisodes {
        unsavedEpisode.podcastId = podcast.id
        episodes.append(try unsavedEpisode.insertAndFetch(db, as: Episode.self))
      }
      if !episodes.isEmpty {
        try RecommendationRepo.updateInferredFreshnessCadence(db, podcastID: podcast.id)
      }
      return PodcastSeries(podcast: podcast, episodes: episodes)
    }
  }

  @discardableResult
  func updateSeriesFromFeed(
    podcast: Podcast,
    updatedPodcast: Podcast?,
    unsavedEpisodes: [UnsavedEpisode],
    existingEpisodes: [FeedMergeEpisode]
  ) async throws -> NewEpisodeAutomation? {
    let now = Container.shared.dateProvider().now
    let result = try await writer.write { db in
      // Future-dated episodes, such as pinned trailers, would hide newer releases.
      let newestStoredPubDate =
        try Episode
        .filter(Episode.Columns.podcastId == podcast.id)
        .filter(Episode.Columns.pubDate <= now)
        .select(max(Episode.Columns.pubDate), as: Date.self)
        .fetchOne(db)
      var insertedEpisodes = [Episode](capacity: unsavedEpisodes.count)
      var publisherTranscriptWorkCreated = false

      let lastUpdateAssignment = Podcast.Columns.lastUpdate.set(to: Date())
      if let updatedPodcast {
        try Podcast
          .withID(updatedPodcast.id)
          .updateAll(db, updatedPodcast.rssColumnAssignments + [lastUpdateAssignment])
      } else {
        try Podcast
          .withID(podcast.id)
          .updateAll(db, [lastUpdateAssignment])
      }

      for existingEpisode in existingEpisodes {
        try Episode
          .withID(existingEpisode.id)
          .updateAll(db, existingEpisode.rssColumnAssignments)
        let publisherReferences = try PublisherTranscriptReference.decodeReferences(
          from: existingEpisode.publisherTranscriptReferencesJSON
        )
        if !publisherReferences.contains(where: { $0.format != nil }) {
          try PublisherTranscriptImportJob
            .filter(
              PublisherTranscriptImportJob.Columns.episodeId == existingEpisode.id
            )
            .deleteAll(db)
        }
      }

      for var unsavedEpisode in unsavedEpisodes {
        unsavedEpisode.podcastId = podcast.id
        let episode = try unsavedEpisode.insertAndFetch(db, as: Episode.self)
        insertedEpisodes.append(episode)
        if !episode.hasTranscript,
          episode.publisherTranscriptReferences.contains(where: { $0.format != nil })
        {
          try PublisherTranscriptImportStore.insert(
            episode.id,
            nextAttemptAt: now,
            in: db
          )
          publisherTranscriptWorkCreated = true
        }
      }

      if !unsavedEpisodes.isEmpty || !existingEpisodes.isEmpty {
        try RecommendationRepo.updateInferredFreshnessCadence(db, podcastID: podcast.id)
      }

      return (
        automation: try automateNewEpisodes(
          db,
          podcastID: podcast.id,
          insertedEpisodes: insertedEpisodes,
          newestStoredPubDate: newestStoredPubDate
        ),
        publisherTranscriptWorkCreated: publisherTranscriptWorkCreated
      )
    }
    if result.publisherTranscriptWorkCreated {
      publisherTranscriptProcessor.workBecameAvailable()
    }
    return result.automation
  }

  // Only a subscribed podcast's episodes newer than the newest already-published
  // one it stored before this refresh count as new; the rest are back catalog.
  private func automateNewEpisodes(
    _ db: Database,
    podcastID: Podcast.ID,
    insertedEpisodes: [Episode],
    newestStoredPubDate: Date?
  ) throws -> NewEpisodeAutomation? {
    guard !insertedEpisodes.isEmpty,
      let podcast = try Podcast.withID(podcastID).fetchOne(db),
      podcast.subscribed
    else { return nil }

    let newEpisodes =
      insertedEpisodes
      .filter { episode in
        guard let newestStoredPubDate else { return true }
        return episode.pubDate > newestStoredPubDate
      }
      .sorted { $0.pubDate > $1.pubDate }
    let backCatalogCount = insertedEpisodes.count - newEpisodes.count
    if backCatalogCount > 0 {
      Self.log.debug(
        """
        automateNewEpisodes: skipping \(backCatalogCount) inserted episodes older than \
        podcast \(podcastID)'s newest stored episode
        """
      )
    }
    guard !newEpisodes.isEmpty else { return nil }

    let queueMode = podcast.queueAllEpisodes
    if queueMode != .never {
      let episodesToQueue: [Episode]
      if let autoQueueLimit = podcast.autoQueueLimit {
        // Keep only this podcast's `autoQueueLimit` newest episodes, evicting its
        // own oldest queued episodes to make room for the surviving incoming ones.
        episodesToQueue = try queue.limitPodcast(
          db,
          podcastID: podcastID,
          incoming: newEpisodes,
          to: autoQueueLimit
        )
      } else {
        episodesToQueue = Array(newEpisodes.prefix(PodcastSettings.defaultAutoQueueLimit))
      }
      // Newest first on top, oldest first on bottom, matching separate refreshes.
      if !episodesToQueue.isEmpty {
        if queueMode == .onTop {
          try queue.unshift(db, episodesToQueue.map(\.id))
        } else {
          try queue.append(db, episodesToQueue.reversed().map(\.id))
        }
      }
    }
    return NewEpisodeAutomation(podcast: podcast, episodes: newEpisodes)
  }

  // MARK: - Podcast Writers

  @discardableResult
  func deletePodcast(_ podcastIDs: [Podcast.ID]) async throws -> Int {
    let playManager = playManager
    let queue = queue
    let reader = reader
    let writer = writer
    let deletion = try await transcriptionProcessor.reconcileDeletion(
      resolvingEpisodeIDs: {
        Set(
          try await reader.read { db in
            try Episode.all()
              .filter { podcastIDs.contains($0.podcastId) }
              .selectID()
              .fetchAll(db)
          }
        )
      },
      perform: {
        try await writer.write { db in
          let episodesToDelete = try Episode.all()
            .filter { podcastIDs.contains($0.podcastId) }
            .fetchAll(db)

          let queuedEpisodeIDs =
            try Episode.all()
            .queued()
            .filter { podcastIDs.contains($0.podcastId) }
            .selectID()
            .fetchAll(db)
          try queue.dequeue(db, queuedEpisodeIDs)

          // Cascades to episodes via FK ON DELETE CASCADE.
          let deletedCount = try Podcast.withIDs(podcastIDs).deleteAll(db)
          let candidateCachedFilenames = Set(
            episodesToDelete.compactMap { $0.cachedURL?.lastPathComponent }
          )
          let retainedCachedFilenames = Set(
            try Episode
              .filter(candidateCachedFilenames.contains(Episode.Columns.cachedFilename))
              .select(Episode.Columns.cachedFilename, as: String.self)
              .fetchAll(db)
          )
          let cachedEpisodesToDelete = episodesToDelete.filter { episode in
            guard let cachedFilename = episode.cachedURL?.lastPathComponent else { return false }
            return !retainedCachedFilenames.contains(cachedFilename)
          }
          return (
            deletedCount: deletedCount,
            episodes: episodesToDelete,
            cachedEpisodes: cachedEpisodesToDelete
          )
        }
      }
    )

    let deletedEpisodeIDs = Set(deletion.episodes.map(\.id))
    await cacheManager.cancelDownloads(for: deletedEpisodeIDs)
    await playManager.removeDeletedEpisodes(deletedEpisodeIDs)

    for episode in deletion.cachedEpisodes {
      if let url = episode.cachedURL {
        do {
          let disposition = try await cacheFileStore.removeFileIfUnreferenced(url)
          switch disposition {
          case .retained:
            Self.log.debug("Preserved referenced cached file at: \(url)")
          case .removed:
            Self.log.debug("Removed cached file at: \(url)")
          case .alreadyMissing:
            Self.log.debug(
              "Cached file already missing at \(url) for episode \(episode.toString)"
            )
          }
        } catch {
          Self.log.caughtError(
            "Failed to remove cached file at \(url) for episode \(episode.toString)",
            error
          )
        }
      }
    }

    return deletion.deletedCount
  }

  @discardableResult
  func deletePodcast(_ podcastID: Podcast.ID) async throws -> Bool {
    try await deletePodcast([podcastID]) > 0
  }

  // MARK: - Tag Writers

  @discardableResult
  func insertTag(_ unsavedTag: UnsavedTag) async throws -> Tag {
    try await writer.write { db in
      try unsavedTag.insertAndFetch(db, as: Tag.self)
    }
  }

  @discardableResult
  func updateTag(_ tagID: Tag.ID, name: String, icon: LucideIcon) async throws -> Bool {
    let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedName.isEmpty else {
      throw DatabaseError(message: "Tag name cannot be empty")
    }

    return try await writer.write { db in
      try Tag
        .withID(tagID)
        .updateAll(
          db,
          Tag.Columns.name.set(to: normalizedName),
          Tag.Columns.icon.set(to: icon.databaseValue)
        )
    } > 0
  }

  @discardableResult
  func deleteTag(_ tagID: Tag.ID) async throws -> Bool {
    try await writer.write { db in
      let deleted = try Tag.withID(tagID).deleteAll(db)
      // Tag IDs live inside smartList.filter JSON, so there's no FK cascade:
      // strip any condition naming the deleted tag from every stored filter in
      // the same transaction.
      for smartList in try SmartList.fetchAll(db) {
        let scrubbed = smartList.filter.removingTag(tagID)
        guard scrubbed != smartList.filter else { continue }
        try SmartList
          .withID(smartList.id)
          .updateAll(db, SmartList.Columns.filter.set(to: scrubbed.databaseValue))
      }
      return deleted
    } > 0
  }

  func addTag(_ tagID: Tag.ID, to podcastID: Podcast.ID) async throws {
    try await writer.write { db in
      try PodcastTag(podcastId: podcastID, tagId: tagID).insert(db)
    }
  }

  @discardableResult
  func removeTag(_ tagID: Tag.ID, from podcastID: Podcast.ID) async throws -> Bool {
    try await writer.write { db in
      try PodcastTag
        .filter(
          PodcastTag.Columns.podcastId == podcastID
            && PodcastTag.Columns.tagId == tagID
        )
        .deleteAll(db)
    } > 0
  }

  func addTag(_ tagID: Tag.ID, toPodcasts podcastIDs: [Podcast.ID]) async throws {
    guard !podcastIDs.isEmpty else { return }

    try await writer.write { db in
      for podcastID in podcastIDs {
        try PodcastTag(podcastId: podcastID, tagId: tagID).insert(db, onConflict: .ignore)
      }
    }
  }

  @discardableResult
  func removeTag(_ tagID: Tag.ID, fromPodcasts podcastIDs: [Podcast.ID]) async throws -> Int {
    guard !podcastIDs.isEmpty else { return 0 }

    return try await writer.write { db in
      try PodcastTag
        .filter(
          PodcastTag.Columns.tagId == tagID
            && podcastIDs.contains(PodcastTag.Columns.podcastId)
        )
        .deleteAll(db)
    }
  }

  func addTag(_ tagID: Tag.ID, to episodeID: Episode.ID) async throws {
    try await writer.write { db in
      try EpisodeTag(episodeId: episodeID, tagId: tagID).insert(db)
    }
  }

  @discardableResult
  func removeTag(_ tagID: Tag.ID, from episodeID: Episode.ID) async throws -> Bool {
    try await writer.write { db in
      try EpisodeTag
        .filter(
          EpisodeTag.Columns.episodeId == episodeID
            && EpisodeTag.Columns.tagId == tagID
        )
        .deleteAll(db)
    } > 0
  }

  func addTag(_ tagID: Tag.ID, toEpisodes episodeIDs: [Episode.ID]) async throws {
    guard !episodeIDs.isEmpty else { return }

    try await writer.write { db in
      for episodeID in episodeIDs {
        try EpisodeTag(episodeId: episodeID, tagId: tagID).insert(db, onConflict: .ignore)
      }
    }
  }

  @discardableResult
  func removeTag(_ tagID: Tag.ID, fromEpisodes episodeIDs: [Episode.ID]) async throws -> Int {
    guard !episodeIDs.isEmpty else { return 0 }

    return try await writer.write { db in
      try EpisodeTag
        .filter(
          EpisodeTag.Columns.tagId == tagID
            && episodeIDs.contains(EpisodeTag.Columns.episodeId)
        )
        .deleteAll(db)
    }
  }

  // MARK: - Episode Writers

  @discardableResult
  func upsertPodcastEpisodes(_ unsavedPodcastEpisodes: [UnsavedPodcastEpisode])
    async throws -> [PodcastEpisode]
  {
    guard !unsavedPodcastEpisodes.isEmpty
    else { return [] }

    return try await writer.write { db in
      var upsertedPodcastsByFeedURL: IdentifiedArray<FeedURL, Podcast> =
        IdentifiedArray(id: \.feedURL)
      var upsertedPodcastsByITunesID: IdentifiedArray<ITunesPodcastID?, Podcast> =
        IdentifiedArray(id: \.iTunesID)
      var affectedPodcastIDs = Set<Podcast.ID>()

      let podcastEpisodes = try unsavedPodcastEpisodes.map { unsavedPodcastEpisode in
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
            doUpdate: { excluded in
              var assignments = unsavedPodcast.rssUpsertAssignments(excluded)
              if unsavedPodcast.iTunesID != nil {
                // In DO UPDATE, the bare column is the existing row's value:
                // backfill iTunesID only when the existing row lacks one.
                assignments.append(
                  Podcast.Columns.iTunesID.set(
                    to: Podcast.Columns.iTunesID ?? excluded[Podcast.Columns.iTunesID]
                  )
                )
              }
              return assignments
            }
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
        affectedPodcastIDs.insert(podcast.id)
        return PodcastEpisode(podcast: podcast, episode: episode)
      }

      for podcastID in affectedPodcastIDs {
        try RecommendationRepo.updateInferredFreshnessCadence(db, podcastID: podcastID)
      }
      return podcastEpisodes
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
  func markSubscribed(_ podcastIDs: [Podcast.ID], level: Logger.Level) async throws -> Int {
    try await _setSubscribedColumn(podcastIDs, to: true, level: level)
  }

  @discardableResult
  func markSubscribed(_ podcastID: Podcast.ID, level: Logger.Level) async throws -> Bool {
    try await _setSubscribedColumn([podcastID], to: true, level: level) > 0
  }

  @discardableResult
  func markUnsubscribed(_ podcastIDs: [Podcast.ID]) async throws -> Int {
    try await _setSubscribedColumn(podcastIDs, to: false, level: .debug)
  }

  @discardableResult
  func markUnsubscribed(_ podcastID: Podcast.ID) async throws -> Bool {
    try await markUnsubscribed([podcastID]) > 0
  }

  @discardableResult
  func updateITunesID(_ podcastID: Podcast.ID, iTunesID: ITunesPodcastID) async throws -> Bool {
    Self.log.debug("updateITunesID: \(podcastID) to \(iTunesID)")

    return try await writer.write { db in
      try Podcast
        .withID(podcastID)
        .updateAll(db, Podcast.Columns.iTunesID.set(to: iTunesID))
    } > 0
  }

  func updateLastUpdates(
    _ refreshes: [(id: Podcast.ID, lastUpdate: Date, feedValidators: HTTPValidators?)]
  ) async throws {
    guard !refreshes.isEmpty else { return }
    Self.log.trace("updateLastUpdates: \(refreshes.count) podcasts")

    try await writer.write { db in
      for (podcastID, lastUpdate, feedValidators) in refreshes {
        let feedValidatorsBuild =
          feedValidators == nil ? nil : UnsavedPodcast.currentFeedValidatorsBuild
        try Podcast
          .withID(podcastID)
          .updateAll(
            db,
            Podcast.Columns.lastUpdate.set(to: lastUpdate),
            Podcast.Columns.feedETag.set(to: feedValidators?.eTag),
            Podcast.Columns.feedLastModified.set(to: feedValidators?.lastModified),
            Podcast.Columns.feedValidatorsBuild.set(to: feedValidatorsBuild),
            Podcast.Columns.refreshFailureCount.set(to: 0),
            Podcast.Columns.refreshBackoffUntil.set(to: nil)
          )
      }
    }
  }

  func recordRefreshFailures(
    _ failures: [(id: Podcast.ID, failureCount: Int, backoffUntil: Date)]
  ) async throws {
    guard !failures.isEmpty else { return }
    Self.log.trace("recordRefreshFailures: \(failures.count) podcasts")

    try await writer.write { db in
      for (podcastID, failureCount, backoffUntil) in failures {
        try Podcast
          .withID(podcastID)
          .updateAll(
            db,
            Podcast.Columns.refreshFailureCount.set(to: failureCount),
            Podcast.Columns.refreshBackoffUntil.set(to: backoffUntil)
          )
      }
    }
  }

  @discardableResult
  func updatePodcastSettings(_ podcastID: Podcast.ID, _ settings: PodcastSettings) async throws
    -> Bool
  {
    Self.log.debug("updatePodcastSettings: \(podcastID) to \(settings)")

    return try await writer.write { db in
      try Podcast
        .withID(podcastID)
        .updateAll(
          db,
          Podcast.Columns.silenceMode.set(to: settings.silenceMode),
          Podcast.Columns.quietAudioProtection.set(to: settings.quietAudioProtection),
          Podcast.Columns.defaultPlaybackRate.set(to: settings.defaultPlaybackRate),
          Podcast.Columns.queueAllEpisodes.set(to: settings.queueAllEpisodes),
          Podcast.Columns.autoQueueLimit.set(to: settings.autoQueueLimit),
          Podcast.Columns.cacheAllEpisodes.set(to: settings.cacheAllEpisodes),
          Podcast.Columns.alwaysTranscribeNewEpisodes.set(
            to: settings.alwaysTranscribeNewEpisodes
          ),
          Podcast.Columns.notifyNewEpisodes.set(to: settings.notifyNewEpisodes),
          Podcast.Columns.freshnessCadence.set(to: settings.freshnessCadence)
        )
    } > 0
  }

  // MARK: - Episode Attribute Writers

  @discardableResult
  func updateDuration(_ episodeID: Episode.ID, duration: CMTime) async throws -> Bool {
    Self.log.debug("updateDuration: \(episodeID) to \(duration)")

    return try await writer.write { db in
      try Episode
        .withID(episodeID)
        .updateAll(db, Episode.Columns.duration.set(to: duration))
    } > 0
  }

  func claimForDownloadIfUncached(_ episodeID: Episode.ID) async throws -> Bool {
    Self.log.debug("claimForDownloadIfUncached: \(episodeID)")

    return try await writer.write { db in
      try Episode
        .withID(episodeID)
        .filter(Episode.Columns.cachedFilename == nil)
        .filter(Episode.Columns.downloading == false)
        .updateAll(db, Episode.Columns.downloading.set(to: true))
    } > 0
  }

  @discardableResult
  func updateDownloading(_ episodeID: Episode.ID, downloading: Bool) async throws -> Bool {
    Self.log.debug("updateDownloading: \(episodeID) to \(downloading)")

    return try await writer.write { db in
      try Episode
        .withID(episodeID)
        .updateAll(db, Episode.Columns.downloading.set(to: downloading))
    } > 0
  }

  @discardableResult
  func updateCachedFilename(_ episodeID: Episode.ID, cachedFilename: String?) async throws -> Bool {
    Self.log.debug("updateCachedFilename: \(episodeID) to \(cachedFilename ?? "nil")")

    return try await writer.write { db in
      try Episode
        .withID(episodeID)
        .updateAll(db, Episode.Columns.cachedFilename.set(to: cachedFilename))
    } > 0
  }

  @discardableResult
  func updateSaveInCache(_ episodeID: Episode.ID, saveInCache: Bool) async throws -> Bool {
    try await updateSaveInCache([episodeID], saveInCache: saveInCache) > 0
  }

  @discardableResult
  func updateSaveInCache(_ episodeIDs: [Episode.ID], saveInCache: Bool) async throws -> Int {
    Self.log.debug("updateSaveInCache: \(episodeIDs.count) episodes to \(saveInCache)")

    guard !episodeIDs.isEmpty else { return 0 }

    return try await writer.write { db in
      try Episode
        .withIDs(episodeIDs)
        .updateAll(db, Episode.Columns.saveInCache.set(to: saveInCache))
    }
  }

  @discardableResult
  func updateRating(_ episodeIDs: [Episode.ID], rating: EpisodeRating?) async throws -> Int {
    Self.log.debug("updateRating: \(episodeIDs.count) episodes to \(String(describing: rating))")

    guard !episodeIDs.isEmpty else { return 0 }

    return try await writer.write { db in
      try Episode
        .withIDs(episodeIDs)
        .updateAll(
          db,
          Episode.Columns.rating.set(to: rating),
          Episode.Columns.ratingDate.set(to: rating != nil ? Date() : nil)
        )
    }
  }

  @discardableResult
  func updateRating(_ episodeID: Episode.ID, rating: EpisodeRating?) async throws -> Bool {
    try await updateRating([episodeID], rating: rating) > 0
  }

  @discardableResult
  func markFinished(_ episodeIDs: [Episode.ID]) async throws -> Int {
    Self.log.debug("markFinished: \(episodeIDs)")

    guard !episodeIDs.isEmpty else { return 0 }

    return try await writer.write { db in
      try Episode
        .withIDs(episodeIDs)
        .updateAll(
          db,
          Episode.Columns.finishDate.set(to: Date()),
          Episode.Columns.currentTime.set(to: 0),
          Episode.Columns.maxPlaybackTime.set(to: 0),
          Episode.Columns.playbackStarted.set(to: false)
        )
    }
  }

  @discardableResult
  func markFinished(_ episodeID: Episode.ID) async throws -> Bool {
    try await markFinished([episodeID]) > 0
  }

  // MARK: Private Helpers

  private func _setSubscribedColumn(
    _ podcastIDs: [Podcast.ID],
    to subscribed: Bool,
    level: Logger.Level
  ) async throws -> Int {
    Self.log.log(
      level: level,
      "Set \(podcastIDs) to: \(subscribed ? "subscribed" : "unsubscribed")"
    )

    guard !podcastIDs.isEmpty else { return 0 }

    return try await writer.write(level: level) { db in
      if subscribed {
        try Podcast
          .withIDs(podcastIDs)
          .unsubscribed()
          .updateAll(db, Podcast.Columns.subscriptionDate.set(to: Date()))
      } else {
        try Podcast
          .withIDs(podcastIDs)
          .updateAll(db, Podcast.Columns.subscriptionDate.set(to: nil))
      }
    }
  }
}
