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

  private let continuousClockNow = Container.shared.continuousClockNow()
  private let diagnostics = Container.shared.siriCatalogPublicationDiagnostics()
  private let file: SiriCatalogFile
  private let state = ThreadSafe(State.unchanged)
  private let lastPublished = ThreadSafe<SiriCatalog?>(nil)
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

  func publish(_ db: Database, trigger: SiriCatalogPublicationDiagnostics.Trigger) {
    let startedAt = continuousClockNow()
    do {
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
        }
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
            }
          )
          data = try SiriCatalogFile.encode(catalog)
        }
      }
      try file.write(data)
      lastPublished(catalog)
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
}
