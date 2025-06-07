// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import Logging

extension Container {
  internal var appDB: Factory<AppDB> {
    Factory(self) { AppDB._onDisk }.scope(.cached)
  }
}

struct AppDB {
  private static let log = Log.as(LogSubsystem.Database.appDB)

  #if DEBUG
  static func inMemory(migrate: Bool = true) -> AppDB {
    do {
      let dbQueue = try DatabaseQueue(configuration: makeConfiguration())
      return try AppDB(dbQueue, migrate: migrate)
    } catch {
      Assert.fatal("Failed to initialize inMemory AppDB queue: \(ErrorKit.message(for: error))")
    }
  }
  #endif

  fileprivate static let _onDisk = {
    do {
      let dbPool = try DatabasePool(
        path: URL.documentsDirectory.appendingPathComponent("db.sqlite").path,
        configuration: makeConfiguration()
      )
      return try AppDB(dbPool)
    } catch {
      Assert.fatal("Failed to initialize onDisk AppDB pool: \(ErrorKit.message(for: error))")
    }
  }()

  #if DEBUG
  static let onDisk = { _onDisk }()
  static func onDisk(_ fileName: String) -> AppDB {
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

  private static func makeConfiguration() -> Configuration {
    var config = Configuration()

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
