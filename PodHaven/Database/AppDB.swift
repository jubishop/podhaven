// Copyright Justin Bishop, 2025

import Foundation
import GRDB

struct AppDB: Sendable {
  #if DEBUG
    static func empty() -> AppDB {
      do {
        let dbQueue = try DatabaseQueue(configuration: makeConfiguration())
        return try AppDB(dbQueue)
      } catch {
        fatalError("Failed to initialize empty AppDB: \(error)")
      }
    }
  #endif

  private static let _shared = {
    do {
      let dbPool = try DatabasePool(
        path: URL.documentsDirectory.appendingPathComponent("db.sqlite").path,
        configuration: makeConfiguration()
      )
      return try AppDB(dbPool)
    } catch {
      fatalError("Failed to initialize shared AppDB: \(error)")
    }
  }()
  static func shared(_ key: RepoAccessKey) -> AppDB { _shared }
  static func shared(_ key: QueueAccessKey) -> AppDB { _shared }
  #if DEBUG
    static let shared = { _shared }()
  #endif

  // MARK: - Private Static Helpers

  private static func makeConfiguration() -> Configuration {
    var config = Configuration()
    #if DEBUG
      config.publicStatementArguments = true
    #endif
    return config
  }

  // MARK: - Initialization

  let db: DatabaseWriter
  private init(_ db: some DatabaseWriter) throws {
    self.db = db
    try Schema.makeMigrator().migrate(db)
  }
}
