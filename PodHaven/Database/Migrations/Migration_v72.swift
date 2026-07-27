// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Logging

extension Schema {
  static func migrateV72(_ db: Database) throws {
    try db.create(table: "episodeTranscriptionQueue") { table in
      table.autoIncrementedPrimaryKey("position")
      table.column("episodeId", .integer).notNull().unique()
        .references("episode", onDelete: .cascade)
    }

    let defaults = Container.shared.standardDefaults()
    guard let data = defaults.data(forKey: "transcriptionQueue") else { return }

    let episodeIDs: [Int64]
    do {
      episodeIDs = try JSONDecoder().decode([Int64].self, from: data)
    } catch {
      log.caughtError(
        "v72 migration: discarded malformed transcriptionQueue",
        error,
        level: { _ in .info }
      )
      return
    }

    for episodeID in episodeIDs {
      try db.execute(
        sql: """
          INSERT OR IGNORE INTO episodeTranscriptionQueue (episodeId)
          SELECT ?
          WHERE EXISTS (SELECT 1 FROM episode WHERE id = ?)
          """,
        arguments: [episodeID, episodeID]
      )
    }
  }
}
