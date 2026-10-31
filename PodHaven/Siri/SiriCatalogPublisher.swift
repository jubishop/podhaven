// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Logging

extension Container {
  var siriCatalogFile: Factory<SiriCatalogFile> {
    Factory(self) {
      guard
        let container = FileManager.default.containerURL(
          forSecurityApplicationGroupIdentifier: AppInfo.appGroupID
        )
      else { Assert.fatal("Siri app group is unavailable") }
      return SiriCatalogFile(url: container.appendingPathComponent("siri-media.json"))
    }
    .scope(.cached)
  }
}

final class SiriCatalogPublisher: TransactionObserver, Sendable {
  private enum State { case unchanged, changed, invalidated }

  private struct Stamp: Decodable {
    let schemaVersion: Int
    let source: SiriCatalog.Source?
  }

  // Bump when the same library would publish a different catalog.
  static let policyVersion = 1

  private let continuousClockNow = Container.shared.continuousClockNow()
  private let diagnostics = Container.shared.siriCatalogPublicationDiagnostics()
  private let file: SiriCatalogFile
  private let state = ThreadSafe(State.unchanged)
  private let lastPublished = ThreadSafe<Data?>(nil)
  private static let log = Log.as("SiriCatalogPublisher")

  init(file: SiriCatalogFile) { self.file = file }

  func observes(eventsOfKind kind: DatabaseEventKind) -> Bool {
    switch kind {
    case .insert(let table), .delete(let table):
      return ["podcast", "episode"].contains(table)
    case .update(let table, let columns):
      let relevant: Set<String> = [
        "title", "feedURL", "guid", "podcastId", "pubDate", "finishDate",
      ]
      return ["podcast", "episode"].contains(table) && !columns.isDisjoint(with: relevant)
    }
  }

  func databaseDidChange(with event: DatabaseEvent) { state(.changed) }

  func databaseWillCommit() {
    guard state() == .changed else { return }
    do {
      try file.invalidate()
      state(.invalidated)
    } catch {
      Self.log.caughtError("Could not invalidate Siri catalog before library commit", error)
    }
  }

  func databaseDidCommit(_ db: Database) {
    guard state() != .unchanged else { return }
    state(.unchanged)
    publish(db, trigger: .commit)
  }

  func databaseDidRollback(_ db: Database) {
    let invalidated = state() == .invalidated
    state(.unchanged)
    guard invalidated, let lastPublished = lastPublished() else { return }
    do { try file.write(lastPublished) } catch {
      Self.log.caughtError("Could not restore Siri catalog after rollback", error)
    }
  }

  func launch(_ db: Database, openDuration: Duration?) {
    let startedAt = continuousClockNow()
    let kept: Data?
    do {
      kept = try keptCatalog(db)
    } catch {
      Self.log.caughtError("Could not keep Siri catalog from an earlier launch", error)
      kept = nil
    }
    let checkDuration = continuousClockNow() - startedAt
    if let kept {
      lastPublished(kept)
      diagnostics.recordSkip(
        openDuration: openDuration,
        checkDuration: checkDuration,
        bytes: kept.count
      )
      return
    }
    do { try file.removeAside() } catch {
      Self.log.caughtError("Could not remove Siri catalog from an earlier launch", error)
    }
    publish(db, trigger: .launch(openDuration: openDuration, checkDuration: checkDuration))
  }

  func publish(_ db: Database, trigger: SiriCatalogPublicationDiagnostics.Trigger) {
    let startedAt = continuousClockNow()
    do {
      let source = try currentSource(db)
      let podcasts =
        try Podcast
        .select(Podcast.Columns.id, Podcast.Columns.feedURL, Podcast.Columns.title)
        .order(Podcast.Columns.id).asRequest(of: Row.self).fetchAll(db)
      let episodes =
        try Episode
        .select(
          Episode.Columns.id,
          Episode.Columns.podcastId,
          Episode.Columns.guid,
          Episode.Columns.title
        )
        .order(Episode.Columns.id).asRequest(of: Row.self).fetchAll(db)
      let episodesByPodcast = Dictionary(grouping: episodes) { row -> Int64 in
        row[Episode.Columns.podcastId]
      }
      var catalog = SiriCatalog(
        podcasts: podcasts.map { podcast in
          let id: Int64 = podcast[Podcast.Columns.id]
          return SiriCatalog.Podcast(
            id: id,
            feed: podcast[Podcast.Columns.feedURL],
            title: podcast[Podcast.Columns.title],
            episodes: (episodesByPodcast[id] ?? [])
              .map {
                SiriCatalog.Episode(
                  id: $0[Episode.Columns.id],
                  guid: $0[Episode.Columns.guid],
                  title: $0[Episode.Columns.title]
                )
              }
          )
        },
        source: source
      )
      let fetchedAt = continuousClockNow()
      var data = try SiriCatalogFile.encode(catalog)
      var omitted: Set<Int64> = []
      if data.count > SiriCatalogFile.maximumBytes {
        let episodesByID = Dictionary(
          uniqueKeysWithValues: catalog.podcasts.flatMap(\.episodes).map { ($0.id, $0) }
        )
        var byPriority =
          try Episode
          .select(Episode.Columns.id, as: Int64.self)
          .order(Episode.unfinished.desc, Episode.Columns.pubDate.desc, Episode.Columns.id.desc)
          .fetchAll(db).compactMap { episodesByID[$0] }
        while data.count > SiriCatalogFile.maximumBytes, !byPriority.isEmpty {
          var excess = data.count - SiriCatalogFile.maximumBytes
          while excess > 0, let episode = byPriority.popLast() {
            omitted.insert(episode.id)
            excess -= episode.estimatedEncodedBytes
          }
          catalog = SiriCatalog(
            podcasts: catalog.podcasts.map { podcast in
              SiriCatalog.Podcast(
                id: podcast.id,
                feed: podcast.feed,
                title: podcast.title,
                episodes: podcast.episodes.filter { !omitted.contains($0.id) }
              )
            },
            source: source
          )
          data = try SiriCatalogFile.encode(catalog)
        }
      }
      try file.write(data)
      lastPublished(data)
      diagnostics.record(
        SiriCatalogPublicationDiagnostics.Publication(
          trigger: trigger,
          fetchDuration: fetchedAt - startedAt,
          writeDuration: continuousClockNow() - fetchedAt,
          podcasts: podcasts.count,
          episodes: episodes.count - omitted.count,
          omittedEpisodes: omitted.count,
          bytes: data.count
        )
      )
    } catch {
      Self.log.caughtError("Could not publish Siri catalog", error)
      do { try file.invalidate() } catch {
        Self.log.caughtError("Could not invalidate unavailable Siri catalog", error)
      }
    }
  }

  // Restores the catalog set aside at launch when it reflects the committed library.
  private func keptCatalog(_ db: Database) throws -> Data? {
    guard let data = try file.asideData(), !data.isEmpty, data.count <= SiriCatalogFile.maximumBytes
    else { return nil }
    let stamp = try JSONDecoder().decode(Stamp.self, from: data)
    guard stamp.schemaVersion == SiriCatalog.currentSchemaVersion,
      try stamp.source == currentSource(db)
    else { return nil }
    try file.restoreAside()
    return data
  }

  private func currentSource(_ db: Database) throws -> SiriCatalog.Source {
    guard
      let revision = try Table("siriCatalogRevision")
        .select(Column("revision"), as: Int64.self).fetchOne(db)
    else { throw DatabaseError(message: "Missing Siri catalog revision") }
    return SiriCatalog.Source(
      revision: revision,
      migrations: try DatabaseMigrator().appliedIdentifiers(db).count,
      policy: Self.policyVersion
    )
  }
}
