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

struct ChartProgressInput: Equatable, Sendable {
  enum Source: String, Encodable {
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
  static let maximumBytes = 64 * 1024
  static let targetBytes = 48 * 1024
  static var fileURL: URL {
    AppInfo.recentLogFileURL.deletingLastPathComponent()
      .appendingPathComponent("chart-progress.ndjson")
  }
  static var attachment: Sentry.Attachment {
    Sentry.Attachment(
      path: fileURL.path,
      filename: "chart-progress.ndjson",
      contentType: "application/x-ndjson"
    )
  }

  private let handler: FileLogHandler
  private static let log = Log.as("ChartProgressDiagnostics")

  fileprivate init() {
    do {
      try FileManager.default.createDirectory(
        at: Self.fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
    } catch {
      Self.log.caughtError("Could not prepare chart diagnostic directory", error)
    }
    handler = FileLogHandler(
      label: "PodHaven/ChartProgressDiagnostics",
      fileURL: Self.fileURL,
      maxFileSizeBytes: Self.maximumBytes,
      targetFileSizeBytes: Self.targetBytes,
      historyPolicy: .preservePreviousSession,
      writeSynchronously: { _ in true }
    )
  }

  func record(_ snapshot: @escaping @Sendable () -> ChartProgressSnapshot) {
    handler.log(
      level: .debug,
      source: "ChartProgressDiagnostics",
      file: #fileID,
      function: #function,
      line: #line
    ) {
      let encoder = JSONEncoder()
      encoder.nonConformingFloatEncodingStrategy = .convertToString(
        positiveInfinity: "+Infinity",
        negativeInfinity: "-Infinity",
        nan: "NaN"
      )
      let data: Data
      do { data = try encoder.encode(snapshot()) } catch {
        Self.log.caughtError("Could not encode chart diagnostic", error)
        return nil
      }
      return ("chart transition", ["chart": .string(String(decoding: data, as: UTF8.self))])
    }
  }
}

struct ChartProgressSnapshot: Encodable, Sendable {
  let schema = 1
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
    animationsDisabled: Bool?
  ) {
    self.instance = instance
    self.revision = revision
    self.sequence = sequence
    self.transition = transition
    uptime = ProcessInfo.processInfo.systemUptime
    source = input.source
    total = input.total
    values = Array(input.values.prefix(8))
    sectorKeys = Array(input.sectorKeys.prefix(8))
    sectorCount = input.values.count
    sum = input.values.reduce(0, +)
    remainder = total - sum
    remainderInserted = total > sum
    let chartTotal = remainderInserted ? total : sum
    if chartTotal.isFinite, chartTotal > 0, input.values.allSatisfy({ $0.isFinite && $0 >= 0 }) {
      proportions = values.map { $0 / chartTotal }
      remainderProportion = remainderInserted ? remainder / chartTotal : nil
    } else {
      proportions = nil
      remainderProportion = nil
    }
    totalClass = Self.classification(total)
    valueClasses = values.map(Self.classification)
    sumClass = Self.classification(sum)
    remainderClass = Self.classification(remainder)
    outOfRange = values.map { !$0.isFinite || $0 < 0 || $0 > input.total }
    if let size {
      width = size.width
      height = size.height
    } else {
      width = nil
      height = nil
    }
    geometryObservation =
      size == nil ? "unmeasured" : (transition == "render" ? "current_render" : "last_render")
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
    Container.shared.chartProgressDiagnostics()
      .record {
        [
          id, revision, sequence, size = self.size, scene = self.scene,
          animationPresent = self.animationPresent, animationsDisabled = self.animationsDisabled
        ] in
        ChartProgressSnapshot(
          input: input,
          instance: id,
          revision: revision,
          sequence: sequence,
          transition: phase.rawValue,
          size: size,
          scene: scene,
          animationPresent: animationPresent,
          animationsDisabled: animationsDisabled
        )
      }
  }
}
