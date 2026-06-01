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
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.playManager) private var playManager

  private var fileManager: any FileManaging { Container.shared.fileManager() }
  private var sharedState: SharedState { Container.shared.sharedState() }

  private static let log = Log.as(LogSubsystem.Database.repo)

  // MARK: - Initialization

  var db: AppDB.Reader { reader }
  private let reader: AppDB.Reader
  private let writer: AppDB.Writer
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

  func allPodcastSeries(
    _ filter: SQLExpression,
    order: SQLOrdering,
    limit: Int
  ) async throws
    -> [PodcastSeries]
  {
    try await reader.read { db in
      try Podcast
        .all()
        .filter(filter)
        .order(order)
        .limit(limit)
        .including(all: Podcast.episodes)
        .asRequest(of: PodcastSeries.self)
        .fetchAll(db)
    }
  }

  // MARK: - Series Readers

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

  // MARK: - Podcast Readers

  func podcast(_ podcastID: Podcast.ID) async throws -> Podcast? {
    try await reader.read { db in
      try Podcast
        .withID(podcastID)
        .fetchOne(db)
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

    return try await writer.write { db in
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
    try await writer.write { db in
      var newEpisodes = [Episode](capacity: unsavedEpisodes.count)

      let lastUpdateAssignment = Podcast.Columns.lastUpdate.set(to: Date())
      if let podcast = podcast {
        try Podcast
          .withID(podcast.id)
          .updateAll(db, podcast.rssColumnAssignments + [lastUpdateAssignment])
      } else {
        try Podcast
          .withID(podcastSeries.id)
          .updateAll(db, [lastUpdateAssignment])
      }

      for existingEpisode in existingEpisodes {
        try Episode
          .withID(existingEpisode.id)
          .updateAll(db, existingEpisode.rssColumnAssignments)
      }

      for var unsavedEpisode in unsavedEpisodes {
        unsavedEpisode.podcastId = podcastSeries.id
        newEpisodes.append(try unsavedEpisode.insertAndFetch(db, as: Episode.self))
      }

      if podcastSeries.podcast.queueAllEpisodes == .onTop {
        try queue.unshift(db, newEpisodes.map(\.id))
      } else if podcastSeries.podcast.queueAllEpisodes == .onBottom {
        try queue.append(db, newEpisodes.map(\.id))
      }

      if podcastSeries.podcast.queueAllEpisodes != .never,
        let autoQueueLimit = podcastSeries.podcast.autoQueueLimit
      {
        try queue.limitPodcast(db, podcastID: podcastSeries.id, to: autoQueueLimit)
      }
      return newEpisodes
    }
  }

  // MARK: - Podcast Writers

  @discardableResult
  func deletePodcast(_ podcastIDs: [Podcast.ID]) async throws -> Int {
    let episodesToDelete = try await reader.read { db in
      try Episode.all()
        .filter { podcastIDs.contains($0.podcastId) }
        .fetchAll(db)
    }

    for episode in episodesToDelete {
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

      if sharedState.onDeck?.id == episode.id {
        await playManager.stop()
        Self.log.debug("Stopped playback for \(episode.toString) because its being deleted")
      }
    }

    return try await writer.write { db in
      let queuedEpisodeIDs =
        try Episode.all()
        .queued()
        .filter { podcastIDs.contains($0.podcastId) }
        .selectID()
        .fetchAll(db)
      try queue.dequeue(db, queuedEpisodeIDs)

      // Cascades to episodes via FK ON DELETE CASCADE.
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
    try await writer.write { db in
      try unsavedTag.insertAndFetch(db, as: Tag.self)
    }
  }

  @discardableResult
  func renameTag(_ tagID: Tag.ID, newName: String) async throws -> Bool {
    let normalizedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedName.isEmpty else {
      throw DatabaseError(message: "Tag name cannot be empty")
    }

    return try await writer.write { db in
      try Tag
        .withID(tagID)
        .updateAll(db, Tag.Columns.name.set(to: normalizedName))
    } > 0
  }

  @discardableResult
  func deleteTag(_ tagID: Tag.ID) async throws -> Bool {
    try await writer.write { db in
      try Tag
        .withID(tagID)
        .deleteAll(db)
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

    return try await writer.write { db in
      try Podcast
        .withID(podcastID)
        .updateAll(db, Podcast.Columns.iTunesID.set(to: iTunesID))
    } > 0
  }

  func updateLastUpdates(_ pairs: [(Podcast.ID, Date)]) async throws {
    guard !pairs.isEmpty else { return }
    Self.log.trace("updateLastUpdates: \(pairs.count) podcasts")

    try await writer.write { db in
      for (podcastID, lastUpdate) in pairs {
        try Podcast
          .withID(podcastID)
          .updateAll(db, Podcast.Columns.lastUpdate.set(to: lastUpdate))
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
          Podcast.Columns.defaultPlaybackRate.set(to: settings.defaultPlaybackRate),
          Podcast.Columns.queueAllEpisodes.set(to: settings.queueAllEpisodes),
          Podcast.Columns.autoQueueLimit.set(to: settings.autoQueueLimit),
          Podcast.Columns.cacheAllEpisodes.set(to: settings.cacheAllEpisodes),
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

  @discardableResult
  func updateCurrentTime(_ episodeID: Episode.ID, currentTime: CMTime) async throws -> Bool {
    Self.log.trace("updateCurrentTime: \(episodeID) to \(currentTime)")

    return try await writer.write(level: .trace) { db in
      try Episode
        .withID(episodeID)
        .updateAll(
          db,
          Episode.Columns.currentTime.set(to: currentTime),
          Episode.Columns.maxPlaybackTime.set(
            to: sqlMax(Episode.Columns.maxPlaybackTime, currentTime)
          )
        )
    } > 0
  }

  // Caller passes the previous-checkpoint position as `playedFrom` so the
  // bitmap OR-marks exactly the seconds elapsed since last save. Backward
  // and zero-progress ranges leave the bitmap untouched.
  @discardableResult
  func updatePlayback(
    _ episodeID: Episode.ID,
    currentTime: CMTime,
    playedFrom: CMTime,
    now: Date
  ) async throws -> Bool {
    Self.log.trace(
      "updatePlayback: \(episodeID) to \(currentTime) (from \(playedFrom))"
    )

    return try await writer.write(level: .trace) { db in
      let row = try Row.fetchOne(
        db,
        Episode
          .withID(episodeID)
          .select(Episode.Columns.duration, Episode.Columns.playbackCoverage)
      )
      guard let row else { return false }

      var assignments: [ColumnAssignment] = [
        Episode.Columns.currentTime.set(to: currentTime),
        Episode.Columns.maxPlaybackTime.set(
          to: sqlMax(Episode.Columns.maxPlaybackTime, currentTime)
        ),
        Episode.Columns.lastPlayedDate.set(to: now),
      ]

      let duration: CMTime? = row[Episode.Columns.duration]
      let durationSeconds = duration?.positiveFiniteSeconds ?? 0
      let startSeconds = playedFrom.positiveFiniteSeconds
      let endSeconds = currentTime.positiveFiniteSeconds

      if durationSeconds > 0, endSeconds > startSeconds {
        let existing: Data? = row[Episode.Columns.playbackCoverage]
        var coverage = PlaybackCoverage(durationSeconds: durationSeconds, data: existing)
        if coverage.mark(startSeconds: startSeconds, endSeconds: endSeconds) {
          assignments.append(Episode.Columns.playbackCoverage.set(to: coverage.data))
        }
      }

      return
        try Episode
        .withID(episodeID)
        .updateAll(db, assignments) > 0
    }
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
          Episode.Columns.maxPlaybackTime.set(to: 0)
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

    return try await writer.write { db in
      try Podcast
        .withIDs(podcastIDs)
        .updateAll(db, Podcast.Columns.subscriptionDate.set(to: subscribed ? Date() : nil))
    }
  }
}
