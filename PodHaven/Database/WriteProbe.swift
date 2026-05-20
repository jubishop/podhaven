// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import Logging

// Temporary diagnostic probe. Logs the rate, affected tables, and a sampled
// backtrace of every committed write transaction, so a runaway DB-write loop
// can be traced back to whatever is performing the writes. Installed only on
// the real on-disk database — test and preview databases are untouched.
// Remove once the investigation it supports is complete.
final class WriteProbe: TransactionObserver, Sendable {
  private static let log = Log.as("WriteProbe")
  private static let backtraceIntervalMs: Int64 = 2_000

  private struct State {
    var tables: Set<String> = []
    var rowEvents = 0
    var lastBacktraceMs: Int64 = 0
  }
  private let accumulator = ThreadSafe<State>(State())

  static func install(on writer: some DatabaseWriter) {
    writer.add(transactionObserver: WriteProbe(), extent: .databaseLifetime)
  }

  // MARK: - TransactionObserver

  func observes(eventsOfKind _: DatabaseEventKind) -> Bool { true }

  func databaseDidChange(with event: DatabaseEvent) {
    let table = event.tableName
    accumulator { state in
      state.tables.insert(table)
      state.rowEvents += 1
    }
  }

  func databaseDidCommit(_: Database) {
    let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
    let snapshot = accumulator { state -> (tables: [String], rowEvents: Int, backtrace: Bool) in
      defer {
        state.tables = []
        state.rowEvents = 0
      }
      guard state.rowEvents > 0 else { return ([], 0, false) }
      let backtrace = nowMs - state.lastBacktraceMs >= Self.backtraceIntervalMs
      if backtrace { state.lastBacktraceMs = nowMs }
      return (state.tables.sorted(), state.rowEvents, backtrace)
    }
    guard snapshot.rowEvents > 0 else { return }

    let tableList = snapshot.tables.joined(separator: ",")
    Self.log.notice("DB commit — tables: \(tableList), \(snapshot.rowEvents) row events")
    if snapshot.backtrace {
      let frames = Thread.callStackSymbols.dropFirst(2).prefix(24).joined(separator: "\n")
      Self.log.notice("DB commit backtrace (sampled):\n\(frames)")
    }
  }

  func databaseDidRollback(_: Database) {
    accumulator { state in
      state.tables = []
      state.rowEvents = 0
    }
  }
}
