// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Logging
import UIKit
import os

extension Container {
  var processActivationDiagnostics: Factory<ProcessActivationDiagnostics> {
    Factory(self) { ProcessActivationDiagnostics() }.scope(.cached)
  }
}

struct ProcessActivationDiagnostics: Sendable {
  enum Milestone: String, CaseIterable, Sendable {
    case launched
    case activated
    case contentInserted
    case contentAppeared
  }

  private struct Mark: Sendable {
    let date: Date
    let uptime: TimeInterval
    let mainThread: Bool
    let availableMemoryBytes: Int
    let thermalPressure: ThermalPressure
  }

  private struct Storage: Sendable {
    var launchApplicationState: String?
    var prewarmed: Bool?
    var marks: [Milestone: Mark] = [:]
  }

  @DynamicInjected(\.dateProvider) private var dateProvider
  @DynamicInjected(\.sharedState) private var sharedState

  private static let log = Log.as("ProcessActivationDiagnostics")

  private let storage = ThreadSafe(Storage())

  fileprivate init() {}

  func recordLaunch(applicationState: UIApplication.State, prewarmed: Bool) {
    let state =
      switch applicationState {
      case .active: "active"
      case .inactive: "inactive"
      case .background: "background"
      @unknown default: "unknown"
      }
    let recorded = storage { storage in
      guard storage.launchApplicationState == nil else { return false }
      storage.launchApplicationState = state
      storage.prewarmed = prewarmed
      return true
    }
    guard recorded else { return }
    Self.log.debug("Process launch state: \(state), prewarmed: \(prewarmed)")
    record(.launched)
  }

  func record(_ milestone: Milestone) {
    let mark = Mark(
      date: dateProvider.now,
      uptime: ProcessInfo.processInfo.systemUptime,
      mainThread: Thread.isMainThread,
      availableMemoryBytes: os_proc_available_memory(),
      thermalPressure: sharedState.thermalPressure
    )
    let recorded = storage { storage in
      guard storage.marks[milestone] == nil else { return false }
      storage.marks[milestone] = mark
      return true
    }
    guard recorded else { return }
    Self.log.debug(
      "Process activation milestone: \(milestone.rawValue)",
      metadata: [
        "activationMilestone": .string(milestone.rawValue),
        "uptime": .stringConvertible(mark.uptime),
        "mainThread": .stringConvertible(mark.mainThread),
        "availableMemoryBytes": .stringConvertible(mark.availableMemoryBytes),
        "thermalPressure": .string(mark.thermalPressure.rawValue),
      ]
    )
  }

  func sentryContext() -> [String: Any] {
    let storage = storage()
    let captureUptime = ProcessInfo.processInfo.systemUptime
    var context: [String: Any] = [
      "captureUptime": captureUptime,
      "milestones": Milestone.allCases.compactMap { milestone -> [String: Any]? in
        guard let mark = storage.marks[milestone] else { return nil }
        return [
          "milestone": milestone.rawValue,
          "timestamp": mark.date.ISO8601Format(.init(includingFractionalSeconds: true)),
          "uptime": mark.uptime,
          "secondsBeforeCapture": captureUptime - mark.uptime,
          "mainThread": mark.mainThread,
          "availableMemoryBytes": mark.availableMemoryBytes,
          "thermalPressure": mark.thermalPressure.rawValue,
        ]
      },
    ]
    if let launchApplicationState = storage.launchApplicationState {
      context["launchApplicationState"] = launchApplicationState
    }
    if let prewarmed = storage.prewarmed {
      context["prewarmed"] = prewarmed
    }
    return context
  }
}
