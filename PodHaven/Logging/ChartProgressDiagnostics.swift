// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Logging
import Sentry
import SwiftUI

extension Container {
  var chartProgressDiagnostics: Factory<ChartProgressDiagnostics> {
    Factory(self) { ChartProgressDiagnostics() }.scope(.cached)
  }
}

struct ChartProgressInput: Equatable {
  enum Source: String, Encodable, Sendable {
    case download, playback, opml, preview
  }

  let source: Source
  let total: Double
  let values: [Double]
  let sectorKeys: [Int]
  let innerRadiusRatio: Double
  let angularInset: Double?
  var numerator: Double? = nil
  var denominator: Double? = nil
  var waitingCount: Int? = nil

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.source == rhs.source && lhs.total.bitPattern == rhs.total.bitPattern
      && lhs.values.map(\.bitPattern) == rhs.values.map(\.bitPattern)
      && lhs.sectorKeys == rhs.sectorKeys
      && lhs.innerRadiusRatio.bitPattern == rhs.innerRadiusRatio.bitPattern
      && bits(lhs.angularInset) == bits(rhs.angularInset)
      && bits(lhs.numerator) == bits(rhs.numerator)
      && bits(lhs.denominator) == bits(rhs.denominator)
      && lhs.waitingCount == rhs.waitingCount
  }

  private static func bits(_ value: Double?) -> UInt64? {
    if let value { return value.bitPattern }
    return nil
  }
}

struct ChartProgressDiagnostics: Sendable {
  static let maximumBytes = 1024 * 1024
  static var directory: URL {
    AppInfo.recentLogFileURL.deletingLastPathComponent()
      .appendingPathComponent("chart-progress", isDirectory: true)
  }

  private let store: ChartProgressStore?
  private static let log = Log.as("ChartProgressDiagnostics")

  fileprivate init() {
    do {
      store = try ChartProgressStore(
        directory: Self.directory,
        session: ChartProgressSession(
          sessionID: FileLogHandler.sessionID,
          version: AppInfo.version,
          buildNumber: AppInfo.buildNumber,
          gitCommitHash: AppInfo.gitCommitHash
        )
      )
    } catch {
      Self.log.caughtError("Could not prepare chart diagnostic store", error)
      store = nil
    }
  }

  func record(_ snapshot: ChartProgressSnapshot) {
    store?.record(snapshot)
  }

  func attachment(sessionID: String) -> Sentry.Attachment {
    let data: Data
    do {
      if let store {
        data = try store.export(sessionID: sessionID)
      } else {
        data = Data("{\"kind\":\"unavailable\",\"reason\":\"store_initialization_failed\"}\n".utf8)
      }
    } catch {
      Self.log.caughtError("Could not export chart diagnostic store", error)
      return Sentry.Attachment(
        data: Data("{\"kind\":\"unavailable\",\"reason\":\"export_failed\"}\n".utf8),
        filename: "chart-progress.ndjson",
        contentType: "application/x-ndjson"
      )
    }
    return Sentry.Attachment(
      data: data,
      filename: "chart-progress.ndjson",
      contentType: "application/x-ndjson"
    )
  }
}

struct ChartProgressSnapshot: Encodable, Sendable {
  let schema = 2
  let timestamp: Double
  let instance: UUID
  let revision: Int
  let sequence: Int
  let transition: String
  let uptime: Double
  let source: ChartProgressInput.Source
  let total: Double
  let values: [Double]
  let sectorKeys: [Int]
  let sectorCount: Int
  let omittedSectorCount: Int
  let sum: Double
  let remainder: Double
  let remainderInserted: Bool
  let proportions: [Double]?
  let remainderProportion: Double?
  let totalClass: String
  let valueClasses: [String]
  let sumClass: String
  let remainderClass: String
  let outOfRange: [Bool]
  let width: Double?
  let height: Double?
  let geometryObservation: String
  let innerRadiusRatio: Double
  let angularInset: Double?
  let numerator: Double?
  let denominator: Double?
  let waitingCount: Int?
  let scene: String
  let animationPresent: Bool?
  let animationsDisabled: Bool?

  init(
    input: ChartProgressInput,
    instance: UUID,
    revision: Int,
    sequence: Int,
    transition: String,
    size: CGSize?,
    scene: String,
    animationPresent: Bool?,
    animationsDisabled: Bool?,
    timestamp: Double = Date().timeIntervalSince1970,
    uptime: Double = ProcessInfo.processInfo.systemUptime,
    sectorCount: Int? = nil,
    sum: Double? = nil,
    valuesValid: Bool? = nil,
    geometryObservation: String? = nil
  ) {
    self.instance = instance
    self.revision = revision
    self.sequence = sequence
    self.transition = transition
    self.uptime = uptime
    self.timestamp = timestamp
    source = input.source
    total = input.total
    values = Array(input.values.prefix(8))
    sectorKeys = Array(input.sectorKeys.prefix(8))
    self.sectorCount = sectorCount ?? input.values.count
    omittedSectorCount = max(0, self.sectorCount - values.count)
    self.sum = sum ?? input.values.reduce(0, +)
    remainder = total - self.sum
    remainderInserted = total > self.sum
    let chartTotal = remainderInserted ? total : self.sum
    if chartTotal.isFinite, chartTotal > 0,
      valuesValid ?? input.values.allSatisfy({ $0.isFinite && $0 >= 0 })
    {
      proportions = values.map { $0 / chartTotal }
      remainderProportion = remainderInserted ? remainder / chartTotal : nil
    } else {
      proportions = nil
      remainderProportion = nil
    }
    totalClass = Self.classification(total)
    valueClasses = values.map(Self.classification)
    sumClass = Self.classification(self.sum)
    remainderClass = Self.classification(remainder)
    outOfRange = values.map { !$0.isFinite || $0 < 0 || $0 > input.total }
    if let size {
      width = size.width
      height = size.height
    } else {
      width = nil
      height = nil
    }
    self.geometryObservation =
      geometryObservation
      ?? (size == nil ? "unmeasured" : (transition == "render" ? "current_render" : "last_render"))
    innerRadiusRatio = input.innerRadiusRatio
    angularInset = input.angularInset
    numerator = input.numerator
    denominator = input.denominator
    waitingCount = input.waitingCount
    self.scene = scene
    self.animationPresent = animationPresent
    self.animationsDisabled = animationsDisabled
  }

  private static func classification(_ value: Double) -> String {
    if value.isNaN { return "nan" }
    if value == .infinity { return "positiveInfinity" }
    if value == -.infinity { return "negativeInfinity" }
    if value == 0 { return "zero" }
    return value < 0 ? "negative" : "positive"
  }
}

@MainActor final class ChartProgressInstance {
  enum Phase: String {
    case render, transaction, appeared, disappeared, scene
  }

  private let id = UUID()
  private var input: ChartProgressInput?
  private var size: CGSize?
  private var scene = "unknown"
  private var animationPresent: Bool?
  private var animationsDisabled: Bool?
  private var revision = 0
  private var sequence = 0
  private var lastPhase: Phase?

  func record(
    _ input: ChartProgressInput,
    size: CGSize? = nil,
    scene: ScenePhase,
    phase: Phase,
    transaction: SwiftUI.Transaction? = nil
  ) {
    guard AppInfo.environment != .preview else { return }
    let inputChanged = self.input != input
    let layoutChanged = size != nil && self.size != size
    let sceneName: String
    switch scene {
    case .active: sceneName = "active"
    case .inactive: sceneName = "inactive"
    case .background: sceneName = "background"
    @unknown default: sceneName = "unknown"
    }
    let animationChanged =
      transaction != nil
      && (animationPresent != (transaction?.animation != nil)
        || animationsDisabled != transaction?.disablesAnimations)
    guard
      inputChanged || layoutChanged || animationChanged || self.scene != sceneName
        || phase == .appeared || phase == .disappeared
        || (phase == .render && lastPhase == .transaction)
    else { return }
    if inputChanged {
      revision += 1
      self.input = input
    }
    if let size { self.size = size }
    self.scene = sceneName
    if let transaction {
      animationPresent = transaction.animation != nil
      animationsDisabled = transaction.disablesAnimations
    }
    sequence += 1
    lastPhase = phase
    Container.shared.chartProgressDiagnostics()
      .record(
        ChartProgressSnapshot(
          input: input,
          instance: id,
          revision: revision,
          sequence: sequence,
          transition: phase.rawValue,
          size: self.size,
          scene: sceneName,
          animationPresent: animationPresent,
          animationsDisabled: animationsDisabled,
          geometryObservation: size != nil
            ? "current_render"
            : (self.size == nil ? "unmeasured" : "last_render")
        )
      )
  }
}
