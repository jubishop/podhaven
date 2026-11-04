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
  // A relevant commit is `committing` from `databaseWillCommit()` until its outcome, and
  // `invalidated` once the catalog file is emptied for it.
  private enum Transaction { case unchanged, finishChanged, changed, committing, invalidated }

  private struct Published {
    let data: Data
    let omitsEpisodes: Bool
  }

  private struct Built: Sendable {
    let data: Data
    let podcasts: Int
    let episodes: Int
    let omittedEpisodes: Int
    let fetchedAt: ContinuousClock.Instant
  }

  private struct Status {
    var transaction = Transaction.unchanged
    // Landed relevant commits, and how many of them the last finished publication reflects.
    var commits = 0
    var settled = 0
    // The last finished publication's catalog, or nil when it failed.
    var published: Published?
    var running: AsyncLatch<Void>?

    var commitPending: Bool { [.committing, .invalidated].contains(transaction) }
    var current: Published? { settled == commits ? published : nil }

    mutating func startPublishing() -> AsyncLatch<Void>? {
      guard running == nil else { return nil }
      let run = AsyncLatch<Void>()
      running = run
      return run
    }
  }

  // Finish state reaches the catalog only through which episodes it omits.
  private final class FinishObserver: TransactionObserver, Sendable {
    private let status: ThreadSafe<Status>

    init(status: ThreadSafe<Status>) { self.status = status }

    func observes(eventsOfKind kind: DatabaseEventKind) -> Bool {
      guard case .update(let table, let columns) = kind else { return false }
      return table == "episode" && columns.contains("finishDate")
    }

    func databaseDidChange(with event: DatabaseEvent) {
      status { if $0.transaction == .unchanged { $0.transaction = .finishChanged } }
    }

    func databaseDidCommit(_ db: Database) {}

    func databaseDidRollback(_ db: Database) {}
  }

  private struct Stamp: Decodable {
    let schemaVersion: Int
    let source: SiriCatalog.Source?
  }

  // Bump when the same library would publish a different catalog.
  static let policyVersion = 1

  private let continuousClockNow = Container.shared.continuousClockNow()
  private let diagnostics = Container.shared.siriCatalogPublicationDiagnostics()
  private let file: SiriCatalogFile
  private let reader: any DatabaseReader
  private let status: ThreadSafe<Status>
  private let finishObserver: FinishObserver
  private static let log = Log.as("SiriCatalogPublisher")

  init(file: SiriCatalogFile, reader: any DatabaseReader) {
    let status = ThreadSafe(Status())
    self.file = file
    self.reader = reader
    self.status = status
    finishObserver = FinishObserver(status: status)
  }

  // The caller owns the publisher; the database retaining it would retain itself through `reader`.
  func observe(_ db: Database) {
    db.add(transactionObserver: self, extent: .observerLifetime)
    db.add(transactionObserver: finishObserver, extent: .observerLifetime)
  }

  func observes(eventsOfKind kind: DatabaseEventKind) -> Bool {
    switch kind {
    case .insert(let table), .delete(let table):
      return ["podcast", "episode"].contains(table)
    case .update(let table, let columns):
      let relevant: Set<String> = ["title", "feedURL", "guid", "podcastId", "pubDate"]
      return ["podcast", "episode"].contains(table) && !columns.isDisjoint(with: relevant)
    }
  }

  func databaseDidChange(with event: DatabaseEvent) { status { $0.transaction = .changed } }

  // After launch, the catalog file changes only under the status lock, so no publication can
  // land between this invalidation and the commit's outcome.
  func databaseWillCommit() {
    status { status in
      if status.transaction == .finishChanged {
        let unaffected = status.current?.omitsEpisodes == false
        status.transaction = unaffected ? .unchanged : .changed
      }
      guard status.transaction == .changed else { return }
      status.transaction = .committing
      do {
        try file.invalidate()
        status.transaction = .invalidated
      } catch {
        Self.log.caughtError("Could not invalidate Siri catalog before library commit", error)
      }
    }
  }

  func databaseDidCommit(_ db: Database) {
    let run = status { status -> AsyncLatch<Void>? in
      guard status.transaction != .unchanged else { return nil }
      status.transaction = .unchanged
      status.commits += 1
      return status.startPublishing()
    }
    if let run { Task { await publishCommits(run) } }
  }

  func databaseDidRollback(_ db: Database) {
    let run = status { status -> AsyncLatch<Void>? in
      let transaction = status.transaction
      status.transaction = .unchanged
      guard [.committing, .invalidated].contains(transaction) else { return nil }
      guard status.settled == status.commits else { return status.startPublishing() }
      if transaction == .invalidated, let published = status.published {
        do { try file.write(published.data) } catch {
          Self.log.caughtError("Could not restore Siri catalog after rollback", error)
        }
      }
      return nil
    }
    if let run { Task { await publishCommits(run) } }
  }

  func published() async throws {
    guard let running = status({ $0.running }) else { return }
    Self.log.debug("Waiting for the Siri catalog publication")
    try await running.wait()
  }

  func launch(_ db: Database, openDuration: Duration?) {
    let startedAt = continuousClockNow()
    let kept: Published?
    do {
      kept = try keptCatalog(db)
    } catch {
      Self.log.caughtError("Could not keep Siri catalog from an earlier launch", error)
      kept = nil
    }
    let checkDuration = continuousClockNow() - startedAt
    do { try file.removeStaged() } catch {
      Self.log.caughtError("Could not remove a staged Siri catalog from an earlier launch", error)
    }
    if let kept {
      status { $0.published = kept }
      diagnostics.recordSkip(
        openDuration: openDuration,
        checkDuration: checkDuration,
        bytes: kept.data.count
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
      let built = try build(db)
      try file.write(built.data)
      status { status in
        status.settled = status.commits
        status.published = Published(data: built.data, omitsEpisodes: built.omittedEpisodes > 0)
      }
      record(built, trigger: trigger, startedAt: startedAt)
    } catch {
      Self.log.caughtError("Could not publish Siri catalog", error)
      status { status in
        status.settled = status.commits
        status.published = nil
      }
      do { try file.invalidate() } catch {
        Self.log.caughtError("Could not invalidate unavailable Siri catalog", error)
      }
    }
  }

  // Publishes from read snapshots until the catalog reflects every relevant commit, discarding
  // any catalog a later commit made stale. A pending relevant commit stops the run; its outcome
  // starts another. The background task keeps a background write's catalog from waiting for the
  // next launch.
  private func publishCommits(_ run: AsyncLatch<Void>) async {
    let backgroundTask = await BackgroundTask.start(withName: "siriCatalogPublication")
    while true {
      let target = status { status -> Int? in
        guard status.settled != status.commits, !status.commitPending else {
          status.running = nil
          return nil
        }
        return status.commits
      }
      guard let target else { break }
      let startedAt = continuousClockNow()
      let built: Built
      do {
        built = try await reader.read { db in try self.build(db) }
        try file.stage(built.data)
      } catch {
        fail(target, error)
        continue
      }
      let installed = status { status -> Result<Bool, any Error> in
        guard status.commits == target, !status.commitPending else { return .success(false) }
        do {
          try file.installStaged()
        } catch {
          return .failure(error)
        }
        status.settled = target
        status.published = Published(data: built.data, omitsEpisodes: built.omittedEpisodes > 0)
        return .success(true)
      }
      switch installed {
      case .success(true):
        record(built, trigger: .commit, startedAt: startedAt)
      case .success(false):
        Self.log.debug("Discarded a Siri catalog publication that a later commit made stale")
      case .failure(let error):
        fail(target, error)
      }
    }
    await backgroundTask.end()
    run.open()
  }

  // Leaves the catalog unavailable until the next relevant commit, unless one landed or is pending.
  private func fail(_ target: Int, _ error: any Error) {
    Self.log.caughtError("Could not publish Siri catalog", error)
    status { status in
      guard status.commits == target, !status.commitPending else { return }
      status.settled = target
      status.published = nil
      do { try file.invalidate() } catch {
        Self.log.caughtError("Could not invalidate unavailable Siri catalog", error)
      }
    }
  }

  private func record(
    _ built: Built,
    trigger: SiriCatalogPublicationDiagnostics.Trigger,
    startedAt: ContinuousClock.Instant
  ) {
    diagnostics.record(
      SiriCatalogPublicationDiagnostics.Publication(
        trigger: trigger,
        fetchDuration: built.fetchedAt - startedAt,
        writeDuration: continuousClockNow() - built.fetchedAt,
        podcasts: built.podcasts,
        episodes: built.episodes,
        omittedEpisodes: built.omittedEpisodes,
        bytes: built.data.count
      )
    )
  }

  private func build(_ db: Database) throws -> Built {
    let source = try currentSource(db, omitsEpisodes: false)
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
      let boundedSource = try currentSource(db, omitsEpisodes: true)
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
          source: boundedSource
        )
        data = try SiriCatalogFile.encode(catalog)
      }
    }
    return Built(
      data: data,
      podcasts: podcasts.count,
      episodes: episodes.count - omitted.count,
      omittedEpisodes: omitted.count,
      fetchedAt: fetchedAt
    )
  }

  // Restores the catalog set aside at launch when it reflects the committed library.
  private func keptCatalog(_ db: Database) throws -> Published? {
    guard let data = try file.asideData(), !data.isEmpty, data.count <= SiriCatalogFile.maximumBytes
    else { return nil }
    let stamp = try JSONDecoder().decode(Stamp.self, from: data)
    guard stamp.schemaVersion == SiriCatalog.currentSchemaVersion, let source = stamp.source
    else { return nil }
    let omitsEpisodes = source.finishRevision != nil
    guard try source == currentSource(db, omitsEpisodes: omitsEpisodes) else { return nil }
    try file.restoreAside()
    return Published(data: data, omitsEpisodes: omitsEpisodes)
  }

  private func currentSource(_ db: Database, omitsEpisodes: Bool) throws -> SiriCatalog.Source {
    guard
      let revisions = try Table("siriCatalogRevision")
        .select(Column("revision"), Column("finishRevision")).fetchOne(db)
    else { throw DatabaseError(message: "Missing Siri catalog revision") }
    let finishRevision: Int64 = revisions["finishRevision"]
    return SiriCatalog.Source(
      revision: revisions["revision"],
      finishRevision: omitsEpisodes ? finishRevision : nil,
      migrations: try DatabaseMigrator().appliedIdentifiers(db).count,
      policy: Self.policyVersion
    )
  }
}
