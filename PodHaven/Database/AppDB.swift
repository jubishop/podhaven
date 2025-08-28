// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import Logging

extension Container {
  internal var appDB: Factory<AppDB> {
    Factory(self) { AppDB._onDisk }.scope(.cached)
  }

  internal var backgroundAppDB: Factory<AppDB> {
    Factory(self) { AppDB._onDiskBackground }.scope(.cached)
  }
}

struct AppDB {
  private static let log = Log.as(LogSubsystem.Database.appDB)

  #if DEBUG
  static func inMemory(migrate: Bool = true) -> AppDB {
    Self.log.debug("creating inMemory AppDB")
    do {
      let dbQueue = try DatabaseQueue(configuration: makeConfiguration())
      return try AppDB(dbQueue, migrate: migrate)
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
      return try AppDB(dbPool)
    } catch {
      Assert.fatal("Failed to initialize onDisk AppDB pool: \(ErrorKit.message(for: error))")
    }
  }()

  fileprivate static let _onDiskBackground = {
    Self.log.debug("creating onDiskBackground AppDB")
    do {
      Assert.precondition(
        AppInfo.environment != .preview,
        "Creating onDiskBackground AppDB in preview is not supported"
      )
      let dbPool = try DatabasePool(
        path: sqlitePath,
        configuration: makeConfiguration(qos: .background)
      )
      return try AppDB(dbPool)
    } catch {
      Assert.fatal(
        "Failed to initialize onDiskBackground AppDB pool: \(ErrorKit.message(for: error))"
      )
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
      return try AppDB(dbQueue)
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

    #if DEBUG
    config.publicStatementArguments = true
    config.prepareDatabase { db in
      db.trace {
        log.trace(
          """
          SQL:
            \($0)
          """
        )
      }
    }
    #endif

    return config
  }

  // MARK: - Initialization

  let db: DatabaseWriter
  private init(_ db: some DatabaseWriter, migrate: Bool = true) throws {
    self.db = db
    if migrate {
      try Schema.makeMigrator().migrate(db)
    }
  }

  #if DEBUG
  func tearDown() {
    do {
      try db.erase()
    } catch {
      Assert.fatal("Failed to erase db in tearDown: \(ErrorKit.message(for: error))")
    }
  }
  #endif
}
