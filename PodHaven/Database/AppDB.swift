// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import Logging

extension Container {
  internal var appDB: Factory<AppDB> {
    Factory(self) { AppDB._onDisk }.scope(.cached)
  }

  internal func initializeAppDB() {
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
    Self.log.debug("creating onDisk AppDB")
    do {
      Assert.precondition(
        AppInfo.environment != .preview,
        "Creating onDisk AppDB in preview is not supported"
      )
      let dbPool = try DatabasePool(path: sqlitePath, configuration: makeConfiguration())
      let appDB = AppDB(dbPool)
      dbPool.add(
        transactionObserver: WriteProbe(enabled: Container.shared.userSettings().$enableWriteProbe),
        extent: .databaseLifetime
      )
      return appDB
    } catch {
      Assert.fatal("Failed to initialize onDisk AppDB pool: \(ErrorKit.message(for: error))")
    }
  }()

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

  static let NoOp = true.sqlExpression

  // MARK: - Private Static Helpers

  private static func makeConfiguration(qos: DispatchQoS? = nil) -> Configuration {
    var config = Configuration()
    if let qos = qos { config.qos = qos }

    config.maximumReaderCount = 10

    return config
  }

  // MARK: - Initialization

  private let db: any DatabaseWriter
  private init(_ db: some DatabaseWriter, migrate: Bool = true) {
    self.db = db
    if migrate {
      Schema.migrate(db)
    }
  }

  var reader: Reader { Reader(self) }
  fileprivate var writer: Writer { Writer(self) }

  @discardableResult func read<Value: Sendable>(
    _ value: @Sendable (Database) throws -> Value
  ) async throws -> Value {
    try await db.read(value)
  }

  @discardableResult func read<Value>(
    _ value: (Database) throws -> Value
  ) throws -> Value {
    try db.read(value)
  }

  func observe<Value: Equatable>(
    _ block: @escaping @Sendable (Database) throws -> Value
  ) -> AsyncValueObservation<Value> {
    ValueObservation.tracking(block)
      .removeDuplicates()
      .values(in: db)
  }

  struct Reader: Sendable {
    private let appDB: AppDB

    fileprivate init(_ appDB: AppDB) {
      self.appDB = appDB
    }

    @discardableResult func read<Value: Sendable>(
      _ value: @Sendable (Database) throws -> Value
    ) async throws -> Value {
      try await appDB.read(value)
    }

    @discardableResult func read<Value>(
      _ value: (Database) throws -> Value
    ) throws -> Value {
      try appDB.read(value)
    }

    func observe<Value: Equatable>(
      _ block: @escaping @Sendable (Database) throws -> Value
    ) -> AsyncValueObservation<Value> {
      appDB.observe(block)
    }
  }

  struct Writer: Sendable {
    private let appDB: AppDB

    fileprivate init(_ appDB: AppDB) {
      self.appDB = appDB
    }

    @discardableResult func write<Value: Sendable>(
      _ label: String? = nil,
      fileID: String = #fileID,
      function: String = #function,
      _ updates: @Sendable (Database) throws -> Value
    ) async throws -> Value {
      let label = label ?? "\(fileID):\(function)"
      let requestedAt = Date()
      AppDB.log.trace("db write requested: \(label)")

      do {
        let result: (value: Value, wait: TimeInterval, transaction: TimeInterval) =
          try await appDB.db.write { db in
            let acquiredAt = Date()
            let wait = acquiredAt.timeIntervalSince(requestedAt)
            AppDB.log.trace("db write acquired: \(label) after \(wait) seconds")

            let value = try updates(db)
            let transaction = Date().timeIntervalSince(acquiredAt)
            return (value, wait, transaction)
          }

        let total = Date().timeIntervalSince(requestedAt)
        AppDB.log.trace(
          """
          db write completed: \(label) \
          total=\(total) seconds \
          wait=\(result.wait) seconds \
          transaction=\(result.transaction) seconds
          """
        )
        return result.value
      } catch {
        AppDB.log.caughtError(
          "db write failed: \(label) after \(Date().timeIntervalSince(requestedAt)) seconds",
          error
        )
        throw error
      }
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
