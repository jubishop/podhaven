// Copyright Justin Bishop, 2024

import Foundation
import GRDB

final class AppDatabase: Sendable {
  private let dbWriter: DatabaseWriter

  #if DEBUG
    static func empty() -> AppDatabase {
      do {
        let dbQueue = try DatabaseQueue(
          configuration: makeConfiguration()
        )
        return try AppDatabase(dbQueue)
      } catch {
        fatalError("Failed to initialize empty AppDatabase: \(error)")
      }
    }
  #endif

  static let shared: AppDatabase = {
    do {
      let dbPool = try DatabasePool(
        path: URL.documentsDirectory.appendingPathComponent("db.sqlite").path,
        configuration: makeConfiguration()
      )
      return try AppDatabase(dbPool)
    } catch {
      fatalError("Failed to initialize shared AppDatabase: \(error)")
    }
  }()

  private static func makeConfiguration() -> Configuration {
    var config = Configuration()
    #if DEBUG
      config.publicStatementArguments = true
    #endif
    return config
  }

  init(_ dbWriter: any DatabaseWriter) throws {
    self.dbWriter = dbWriter
    try Migrations.migrate(dbWriter)
  }

  func read<T>(_ block: (Database) throws -> T) throws -> T {
    try dbWriter.read { db in
      try block(db)
    }
  }

  func write(_ block: @escaping (Database) throws -> Void) throws {
    try dbWriter.write(block)
  }

  var reader: any GRDB.DatabaseReader {
    dbWriter
  }
}
