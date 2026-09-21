// Copyright Justin Bishop, 2025

import Foundation
import Logging

enum Log {
  struct Operation {
    enum State: String {
      case started, encoded, completed, failed
    }

    private let logger: Logger
    private let kind: String
    private let id = UUID().uuidString
    private let startedAt = ProcessInfo.processInfo.systemUptime
    private let count: Int?

    init(_ logger: Logger, kind: String, count: Int? = nil) {
      self.logger = logger
      self.kind = kind
      self.count = count
      record(.started)
    }

    func record(_ state: State, byteCount: Int? = nil) {
      let uptime = ProcessInfo.processInfo.systemUptime
      var metadata: Logger.Metadata = [
        "operationKind": .string(kind),
        "operationID": .string(id),
        "operationState": .string(state.rawValue),
        "uptime": .stringConvertible(uptime),
        "elapsedMs": .stringConvertible((uptime - startedAt) * 1_000),
        "mainThread": .stringConvertible(Thread.isMainThread),
      ]
      if let count { metadata["count"] = .stringConvertible(count) }
      if let byteCount { metadata["byteCount"] = .stringConvertible(byteCount) }
      logger.debug("Operation \(state.rawValue)", metadata: metadata)
    }
  }

  static func `as`(_ categorizable: any LogCategorizable) -> Logger {
    var logger = Logger(
      label: LogKit.buildLabel(
        subsystem: categorizable.subsystem,
        category: categorizable.category
      )
    )
    logger.logLevel = categorizable.level
    return logger
  }

  static func `as`(_ category: String, level: Logger.Level = .debug) -> Logger {
    var logger = Logger(
      label: LogKit.buildLabel(
        subsystem: "PodHaven",
        category: category
      )
    )
    logger.logLevel = level
    return logger
  }
}
