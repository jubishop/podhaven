// Copyright Justin Bishop, 2025

import Foundation
import GRDB

struct AppDB: Sendable {
  #if DEBUG
    static func inMemory() -> AppDB {
      do {
        let dbQueue = try DatabaseQueue(configuration: makeConfiguration())
        return try AppDB(dbQueue)
      } catch {
        fatalError("Failed to initialize inMemory AppDB: \(error)")
      }
    }
  #endif

  private static let _onDisk = {
    do {
      let dbPool = try DatabasePool(
        path: URL.documentsDirectory.appendingPathComponent("db.sqlite").path,
        configuration: makeConfiguration()
      )
      return try AppDB(dbPool)
    } catch {
      fatalError("Failed to initialize onDisk AppDB: \(error)")
    }
  }()
  static func onDisk(_ key: RepoAccessKey) -> AppDB { _onDisk }
  static func onDisk(_ key: QueueAccessKey) -> AppDB { _onDisk }
  #if DEBUG
    static let onDisk = { _onDisk }()
  #endif

  // MARK: - Shorthand Expressions

  static let noOpFilter = true.sqlExpression

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
