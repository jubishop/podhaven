// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB

extension Container {
  var appDB: Factory<AppDB> {
    Factory(self) { AppDB._onDisk }.scope(.cached)
  }
}

struct AppDB: Sendable {
  #if DEBUG
  static func inMemory() -> AppDB {
    do {
      let dbQueue = try DatabaseQueue(configuration: makeConfiguration())
      return try AppDB(dbQueue)
    } catch {
      Log.fatal("Failed to initialize inMemory AppDB queue: \(error)")
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
      Log.fatal("Failed to initialize onDisk AppDB pool: \(error)")
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
      Log.fatal("Failed to initialize onDisk AppDB queue: \(error)")
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
        Log.trace(
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
  private init(_ db: some DatabaseWriter) throws {
    self.db = db
    try Schema.makeMigrator().migrate(db)
  }

  #if DEBUG
  func tearDown() {
    do {
      try db.erase()
    } catch {
      Log.fatal("Failed to erase db in tearDown: \(error)")
    }
  }
  #endif
}
