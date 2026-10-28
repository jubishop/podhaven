// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing
import UIKit

@testable import PodHaven

@Suite("Process activation diagnostics", .container)
struct ProcessActivationDiagnosticsTests {
  @Test("each milestone keeps its first occurrence in timeline order")
  func milestonesKeepFirstOccurrence() throws {
    let fakeDate = Container.shared.fakeDate()
    let diagnostics = Container.shared.processActivationDiagnostics()

    fakeDate.freeze(at: Date(timeIntervalSince1970: 100))
    diagnostics.recordLaunch(applicationState: .background, prewarmed: false)
    fakeDate.freeze(at: Date(timeIntervalSince1970: 200))
    diagnostics.record(.contentAppeared)
    diagnostics.record(.activated)
    fakeDate.freeze(at: Date(timeIntervalSince1970: 300))
    diagnostics.record(.activated)
    diagnostics.record(.contentAppeared)

    let context = diagnostics.sentryContext()
    #expect(context["launchApplicationState"] as? String == "background")
    #expect(context["prewarmed"] as? Bool == false)
    let milestones = try #require(context["milestones"] as? [[String: Any]])
    #expect(
      milestones.map { $0["milestone"] as? String } == ["launched", "activated", "contentAppeared"]
    )
    #expect(
      milestones.map { $0["timestamp"] as? String } == [
        "1970-01-01T00:01:40.000Z", "1970-01-01T00:03:20.000Z", "1970-01-01T00:03:20.000Z",
      ]
    )
    for milestone in milestones {
      #expect(milestone["mainThread"] is Bool)
      #expect(milestone["availableMemoryBytes"] is Int)
      #expect(milestone["thermalPressure"] as? String == ThermalPressure.nominal.rawValue)
      let uptime = try #require(milestone["uptime"] as? TimeInterval)
      let secondsBeforeCapture = try #require(milestone["secondsBeforeCapture"] as? TimeInterval)
      #expect(secondsBeforeCapture >= 0)
      #expect(uptime <= context["captureUptime"] as? TimeInterval ?? 0)
    }
    #expect(JSONSerialization.isValidJSONObject(context))
  }

  @Test("an unlaunched process reports no launch state or milestones")
  func unlaunchedProcessReportsNothing() throws {
    let context = Container.shared.processActivationDiagnostics().sentryContext()

    #expect(context["launchApplicationState"] == nil)
    #expect(context["prewarmed"] == nil)
    let milestones = try #require(context["milestones"] as? [[String: Any]])
    #expect(milestones.isEmpty)
  }

  @Test("only the first launch and first occurrence of a milestone are kept and logged")
  func firstOccurrenceIsLogged() {
    let diagnostics = Container.shared.processActivationDiagnostics()

    let captured = LogCapture.withSink { sink in
      diagnostics.recordLaunch(applicationState: .inactive, prewarmed: true)
      diagnostics.recordLaunch(applicationState: .active, prewarmed: false)
      diagnostics.record(.activated)
      diagnostics.record(.activated)
      return sink.captured()
    }

    let milestoneLogs = captured.filter {
      $0.label == "PodHaven/ProcessActivationDiagnostics"
        && $0.message.hasPrefix("Process activation milestone:")
    }
    #expect(
      milestoneLogs.map(\.message) == [
        "Process activation milestone: launched", "Process activation milestone: activated",
      ]
    )
    let launchLogs = captured.filter {
      $0.label == "PodHaven/ProcessActivationDiagnostics"
        && $0.message.hasPrefix("Process launch state:")
    }
    #expect(launchLogs.map(\.message) == ["Process launch state: inactive, prewarmed: true"])
    let context = diagnostics.sentryContext()
    #expect(context["launchApplicationState"] as? String == "inactive")
    #expect(context["prewarmed"] as? Bool == true)
  }
}
