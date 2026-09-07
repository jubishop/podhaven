// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Logging

// Observes the real database only in eligible environments with the live
// enableWriteProbe setting on. Test and preview databases are not registered.
final class WriteProbe: TransactionObserver, Sendable {
  private static let log = Log.as("WriteProbe")
  private static let backtraceInterval: Duration = .seconds(2)

  private struct State {
    var tables: Set<String> = []
    var rowEvents = 0
    var lastBacktrace: ContinuousClock.Instant?
    var transactionStart: ContinuousClock.Instant?
  }
  private let accumulator = ThreadSafe<State>(State())
  private let enabled: Broadcast<Bool>

  private var isEnabled: Bool {
    AppInfo.environment.allowsDiagnostics && enabled.value
  }

  init(enabled: Broadcast<Bool>) {
    self.enabled = enabled
  }

  // MARK: - TransactionObserver

  // GRDB re-evaluates this before each statement, including after distribution
  // detection finishes or the saved setting changes.
  func observes(eventsOfKind _: DatabaseEventKind) -> Bool { isEnabled }

  func databaseDidChange(with event: DatabaseEvent) {
    guard isEnabled else {
      accumulator { $0 = State() }
      return
    }
    let table = event.tableName
    let instant = Container.shared.continuousClockNow()()
    accumulator { state in
      if state.rowEvents == 0 { state.transactionStart = instant }
      state.tables.insert(table)
      state.rowEvents += 1
    }
  }

  func databaseDidCommit(_: Database) {
    guard isEnabled else {
      accumulator { $0 = State() }
      return
    }
    let instant = Container.shared.continuousClockNow()()
    let snapshot = accumulator {
      state -> (tables: [String], rowEvents: Int, duration: Duration, backtrace: Bool) in
      defer {
        state.tables = []
        state.rowEvents = 0
        state.transactionStart = nil
      }
      guard state.rowEvents > 0, let start = state.transactionStart else {
        return ([], 0, .zero, false)
      }
      let backtrace: Bool
      if let lastBacktrace = state.lastBacktrace {
        backtrace = instant - lastBacktrace >= Self.backtraceInterval
      } else {
        backtrace = true
      }
      if backtrace { state.lastBacktrace = instant }
      return (state.tables.sorted(), state.rowEvents, instant - start, backtrace)
    }
    guard snapshot.rowEvents > 0 else { return }

    let tableList = snapshot.tables.joined(separator: ",")
    Self.log.debug(
      "DB commit — tables: \(tableList), \(snapshot.rowEvents) row events, \(snapshot.duration)"
    )
    if snapshot.backtrace {
      let frames = Thread.callStackSymbols.dropFirst(2).prefix(24).joined(separator: "\n")
      Self.log.debug("DB commit backtrace (sampled):\n\(frames)")
    }
  }

  func databaseDidRollback(_: Database) {
    accumulator { state in
      state.tables = []
      state.rowEvents = 0
      state.transactionStart = nil
    }
  }
}
