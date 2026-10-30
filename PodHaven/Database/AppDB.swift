// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import Logging

extension Container {
  internal var appDB: Factory<AppDB> {
    Factory(self) { AppDB._onDisk }.scope(.cached)
  }

  @MainActor internal func initializeAppDB() {
    siriCatalogPublicationDiagnostics()
      .launching(applicationState: uiApplication().applicationState)
    _ = appDB()
  }

  internal func makeRepo() -> Repo {
    let appDB = appDB()
    return Repo(reader: appDB.reader, writer: appDB.writer)
  }

  internal func makeQueue() -> Queue {
    let appDB = appDB()
    return Queue(reader: appDB.reader, writer: appDB.writer)
  }

  internal func makeRecommendationRepo() -> RecommendationRepo {
    let appDB = appDB()
    return RecommendationRepo(reader: appDB.reader, writer: appDB.writer)
  }

  internal func makeSmartListRepo() -> SmartListRepo {
    let appDB = appDB()
    return SmartListRepo(reader: appDB.reader, writer: appDB.writer)
  }
}

struct AppDB {
  private static let log = Log.as(LogSubsystem.Database.appDB)

  #if DEBUG
  static func inMemory(migrate: Bool = true) -> AppDB {
    Self.log.debug("creating inMemory AppDB")
    do {
      let dbQueue = try DatabaseQueue(configuration: makeConfiguration())
      return AppDB(dbQueue, migrate: migrate)
    } catch {
      Assert.fatal("Failed to initialize inMemory AppDB queue: \(ErrorKit.message(for: error))")
    }
  }
  #endif

  private static let sqlitePath: String =
    AppInfo.documentsDirectory.appendingPathComponent("db.sqlite").path

  fileprivate static let _onDisk = {
    do {
      Assert.precondition(
        AppInfo.environment != .preview,
        "Creating onDisk AppDB in preview is not supported"
      )
      return try launch(path: sqlitePath, siriCatalogFile: Container.shared.siriCatalogFile())
    } catch {
      Assert.fatal("Failed to initialize onDisk AppDB pool: \(ErrorKit.message(for: error))")
    }
  }()

  static func launch(path: String, siriCatalogFile: SiriCatalogFile) throws -> AppDB {
    Self.log.debug("creating onDisk AppDB")
    let now = Container.shared.continuousClockNow()
    let openedAt = now()
    let dbPool = try DatabasePool(path: path, configuration: makeConfiguration())
    let appDB = AppDB(dbPool)
    let openDuration = now() - openedAt
    // Synchronous writer access must precede the queued publication, or it waits for it.
    dbPool.add(
      transactionObserver: WriteProbe(enabled: Container.shared.userSettings().$enableWriteProbe),
      extent: .databaseLifetime
    )
    appDB.startSiriCatalog(siriCatalogFile, openDuration: openDuration)
    return appDB
  }

  #if DEBUG
  static let onDisk = { _onDisk }()
  static func onDisk(_ fileName: String) -> AppDB {
    Self.log.debug("creating onDisk AppDB in \(fileName)")
    do {
      let dbQueue = try DatabaseQueue(
        path: URL.temporaryDirectory.appendingPathComponent(fileName).path,
        configuration: makeConfiguration()
      )
      return AppDB(dbQueue)
    } catch {
      Assert.fatal("Failed to initialize onDisk AppDB queue: \(ErrorKit.message(for: error))")
    }
  }
  #endif

  // MARK: - Shorthand Expression Constants

  static let noOp = true.sqlExpression

  // MARK: - Private Static Helpers

  // Bounds the per-table sampling each `optimize()` may do, so periodic stats
  // maintenance stays cheap even when SQLite examines every table for drift.
  private static let analysisLimit = 400
  private static let optimizeMask = 0x1fffe

  private static func makeConfiguration(qos: DispatchQoS? = nil) -> Configuration {
    var config = Configuration()
    if let qos = qos { config.qos = qos }

    config.maximumReaderCount = 10

    config.prepareDatabase { db in
      try db.execute(sql: "PRAGMA analysis_limit=\(analysisLimit)")
    }

    return config
  }

  // MARK: - Initialization

  private let db: any DatabaseWriter
  private let siriCatalogPublication = ThreadSafe<AsyncLatch<Void>?>(nil)
  private init(_ db: some DatabaseWriter, migrate: Bool = true) {
    self.db = db
    if migrate {
      Schema.migrate(db)
    }
  }

  var reader: Reader { Reader(self) }
  var writer: Writer { Writer(self) }

  // The catalog stays invalid until the first publication, which runs on the writer
  // queue ahead of any library write so a stale snapshot is never readable.
  func startSiriCatalog(_ file: SiriCatalogFile, openDuration: Duration? = nil) {
    let published = AsyncLatch<Void>()
    siriCatalogPublication(published)
    do { try file.invalidate() } catch {
      Self.log.caughtError("Could not invalidate Siri catalog before launch publication", error)
    }
    let publisher = SiriCatalogPublisher(file: file)
    db.asyncWriteWithoutTransaction { db in
      db.add(transactionObserver: publisher, extent: .databaseLifetime)
      publisher.publish(db, trigger: .launch(openDuration: openDuration))
      published.open()
    }
  }

  func siriCatalogPublished() async throws {
    guard let published = siriCatalogPublication(), !published.isOpen else { return }
    Self.log.debug("Waiting for the launch Siri catalog publication")
    try await published.wait()
  }

  struct Reader: Sendable {
    private let appDB: AppDB

    fileprivate init(_ appDB: AppDB) {
      self.appDB = appDB
    }

    @discardableResult func read<Value: Sendable>(
      _ value: @Sendable (Database) throws -> Value
    ) async throws -> Value {
      try await appDB.db.read(value)
    }

    @discardableResult func read<Value>(
      _ value: (Database) throws -> Value
    ) throws -> Value {
      try appDB.db.read(value)
    }

    func observe<Value: Equatable>(
      _ block: @escaping @Sendable (Database) throws -> Value
    ) -> AsyncValueObservation<Value> {
      ValueObservation.tracking(block)
        .removeDuplicates()
        .values(in: appDB.db)
    }

    func observe<Value: Sendable>(
      _ block: @escaping @Sendable (Database) throws -> Value,
      removeDuplicatesBy predicate: @escaping @Sendable (Value, Value) -> Bool
    ) -> AsyncValueObservation<Value> {
      ValueObservation.tracking(block)
        .removeDuplicates(by: predicate)
        .values(in: appDB.db)
    }
  }

  struct Writer: Sendable {
    private let appDB: AppDB

    fileprivate init(_ appDB: AppDB) {
      self.appDB = appDB
    }

    @discardableResult func write<Value: Sendable>(
      level: Logger.Level = .debug,
      label: String? = nil,
      fileID: String = #fileID,
      function: String = #function,
      _ updates: @Sendable (Database) throws -> Value
    ) async throws -> Value {
      let label = label ?? "\(fileID):\(function)"
      let now = Container.shared.continuousClockNow()
      let requestedAt = now()
      AppDB.log.log(level: level, "db write requested: \(label)")

      do {
        let result: (value: Value, wait: Duration, transaction: Duration) =
          try await appDB.db.write { db in
            let acquiredAt = now()
            let wait = acquiredAt - requestedAt
            AppDB.log.log(level: level, "db write acquired: \(label) after \(wait)")

            let value = try updates(db)
            let transaction = now() - acquiredAt
            return (value, wait, transaction)
          }

        AppDB.log.log(
          level: level,
          """
          db write completed: \(label) \
          total=\(now() - requestedAt) \
          wait=\(result.wait) \
          transaction=\(result.transaction)
          """
        )
        return result.value
      } catch {
        AppDB.log.log(level: level, "db write failed: \(label) after \(now() - requestedAt)")
        throw error
      }
    }
  }

  // Writes a self-contained SQLite file (WAL merged via GRDB backup) for sharing or copying.
  func exportSnapshot(to destinationURL: URL) throws {
    let destination = try DatabaseQueue(
      path: destinationURL.path,
      configuration: Self.makeConfiguration()
    )
    try db.backup(to: destination)
  }

  // Keeps one snapshot in the directory; the atomic swap leaves a reader of the
  // earlier snapshot its open file.
  func exportSnapshot(named filename: String, in directory: URL) throws -> URL {
    let fileManager = FileManager.default
    let exportURL = directory.appendingPathComponent(filename)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    for entry in try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    where entry.lastPathComponent != filename {
      try fileManager.removeItem(at: entry)
    }
    let stagingURL = directory.appendingPathComponent(UUID().uuidString)
    try exportSnapshot(to: stagingURL)
    _ = try fileManager.replaceItemAt(exportURL, withItemAt: stagingURL)
    return exportURL
  }

  func exportSnapshotData(in directory: URL) throws -> Data {
    defer {
      do {
        try FileManager.default.removeItem(at: directory)
      } catch {
        if !ErrorKit.isMissingFile(error) {
          Self.log.caughtError("Failed to remove database snapshot at \(directory.path)", error)
        }
      }
    }
    return try Data(contentsOf: exportSnapshot(named: "db.sqlite", in: directory))
  }

  struct FileStats: Sendable {
    let pageCount: Int
    let freelistCount: Int
    let pageSize: Int

    var byteCount: Int { pageCount * pageSize }
    var freeByteCount: Int { freelistCount * pageSize }
    var freeFraction: Double {
      pageCount > 0 ? Double(freelistCount) / Double(pageCount) : 0
    }
  }

  func fileStats() async throws -> FileStats {
    try await db.read { db in
      FileStats(
        pageCount: try Int.fetchOne(db, sql: "PRAGMA page_count") ?? 0,
        freelistCount: try Int.fetchOne(db, sql: "PRAGMA freelist_count") ?? 0,
        pageSize: try Int.fetchOne(db, sql: "PRAGMA page_size") ?? 0
      )
    }
  }

  // SQLite never refreshes its planner statistics on its own, so the migration's
  // one-time ANALYZE goes stale as the library grows. Re-running optimize on a
  // recurring lifecycle signal re-ANALYZEs only the tables whose stats have
  // drifted. The mask keeps SQLite's default optimize behavior while checking
  // every table, even when this connection did not run the read-heavy queries.
  func optimize() async throws {
    try await db.writeWithoutTransaction { db in
      try db.execute(sql: "PRAGMA optimize=\(Self.optimizeMask)")
    }
  }

  #if DEBUG
  var unsafeTestDB: any DatabaseWriter { db }

  func tearDown() {
    do {
      try db.erase()
    } catch {
      Assert.fatal("Failed to erase db in tearDown: \(ErrorKit.message(for: error))")
    }
  }
  #endif
}
