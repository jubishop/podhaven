// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Logging
import Tagged

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

final class SiriCatalogPublisher: TransactionObserver {
  private let file: SiriCatalogFile
  private enum State { case unchanged, changed, invalidated }
  private var state = State.unchanged
  private var lastPublished: SiriCatalog?
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

  func databaseDidChange(with event: DatabaseEvent) { state = .changed }

  func databaseWillCommit() {
    guard state == .changed else { return }
    do {
      try file.invalidate()
      state = .invalidated
    } catch {
      Self.log.caughtError("Could not invalidate Siri catalog before library commit", error)
    }
  }

  func databaseDidCommit(_ db: Database) {
    guard state != .unchanged else { return }
    state = .unchanged
    publish(db)
  }

  func databaseDidRollback(_ db: Database) {
    let invalidated = state == .invalidated
    state = .unchanged
    guard invalidated, let lastPublished else { return }
    do { try file.write(lastPublished) } catch {
      Self.log.caughtError("Could not restore Siri catalog after rollback", error)
    }
  }

  func publish(_ db: Database) {
    do {
      let podcasts = try Podcast.order(Podcast.Columns.id).fetchAll(db)
      let episodes = try Episode.order(Episode.Columns.id)
        .including(required: Episode.podcast).asRequest(of: PodcastEpisode.self).fetchAll(db)
      let entries =
        podcasts.map {
          SiriCatalog.Entry(
            identity: SiriMediaIdentity(
              kind: .podcast,
              id: $0.id.rawValue,
              feed: $0.feedURL.absoluteString
            ),
            title: $0.title,
            podcastTitle: nil
          )
        }
        + episodes.map {
          SiriCatalog.Entry(
            identity: SiriMediaIdentity(
              kind: .episode,
              id: $0.id.rawValue,
              feed: $0.feedURL.absoluteString,
              guid: $0.episode.guid.rawValue
            ),
            title: $0.title,
            podcastTitle: $0.podcastTitle
          )
        }
      let catalog = SiriCatalog(entries: entries)
      try file.write(catalog)
      lastPublished = catalog
      Self.log.debug(
        "Published Siri catalog: podcasts=\(podcasts.count), episodes=\(episodes.count)"
      )
    } catch {
      Self.log.caughtError("Could not publish Siri catalog", error)
      do { try file.invalidate() } catch {
        Self.log.caughtError("Could not invalidate unavailable Siri catalog", error)
      }
    }
  }
}
