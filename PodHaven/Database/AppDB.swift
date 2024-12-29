// Copyright Justin Bishop, 2024

import Foundation
import GRDB

struct AppDB: Sendable {
  #if DEBUG
    static func empty() -> AppDB {
      do {
        let dbQueue = try DatabaseQueue(
          configuration: makeConfiguration()
        )
        return try AppDB(dbQueue)
      } catch {
        fatalError("Failed to initialize empty AppDB: \(error)")
      }
    }
  #endif

  static let shared = {
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

  // MARK: - Columns

  static let currentTimeColumn = Column("currentTime")
  static let mediaColumn = Column("media")
  static let pubDateColumn = Column("pubDate")
  static let queueOrderColumn = Column("queueOrder")

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
    try Migrations.migrate(db)
  }
}
