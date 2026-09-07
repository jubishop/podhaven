// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Observation
import Testing
import UIKit

@testable import PodHaven

@Suite("of diagnostic eligibility tests", .container)
@MainActor struct DiagnosticEligibilityTests {
  private struct Device: DeviceIdentifying {
    let identifierForVendor: UUID?
  }

  private func configure(_ environment: EnvironmentType, personalDevice: Bool = true) {
    let identifier = personalDevice ? "6B915F57-D7FC-4249-8FAD-B71F5D362CEB" : UUID().uuidString
    Container.shared.uiDevice.register { Device(identifierForVendor: UUID(uuidString: identifier)) }
    AppInfo.initializeEnvironment()
    AppInfo.environment = environment
  }

  private func probeDatabase() throws -> (DatabaseQueue, WriteProbe) {
    let database = try DatabaseQueue()
    try database.write { db in
      try db.create(table: "probeTest") { $0.autoIncrementedPrimaryKey("id") }
    }
    let probe = WriteProbe(enabled: Container.shared.userSettings().$enableWriteProbe)
    database.add(transactionObserver: probe, extent: .databaseLifetime)
    return (database, probe)
  }

  private func write(_ database: DatabaseQueue) throws -> [LogCapture.Captured] {
    try database.writeWithoutTransaction { db in
      try LogCapture.withSink { sink in
        try db.inTransaction {
          try db.execute(sql: "INSERT INTO probeTest DEFAULT VALUES")
          return .commit
        }
        return sink.captured().filter { $0.label == "PodHaven/WriteProbe" }
      }
    }
  }

  private func memoryWarning() async throws -> (shown: Bool, logged: Bool) {
    Container.shared.memoryWarningMonitor.reset()
    Container.shared.notifier.reset()
    let alert = Container.shared.alert()
    alert.config = nil
    return try await LogCapture.withSink { sink in
      let monitor = Container.shared.memoryWarningMonitor()
      monitor.start()
      Container.shared.notifier()
        .continuation(for: UIApplication.didReceiveMemoryWarningNotification)
        .yield(Notification(name: UIApplication.didReceiveMemoryWarningNotification))
      try await Wait.until {
        sink.captured().contains { $0.message == "System memory warning received" }
      } _: {
        "Memory warning was not handled"
      }
      return (
        alert.config != nil,
        sink.captured()
          .contains {
            $0.message == "System memory warning received" && $0.level == .warning
          }
      )
    }
  }

  @Test("saved TestFlight probe preference cannot enable App Store diagnostics")
  func savedPreferenceInAppStore() throws {
    configure(.testFlight)
    let settings = Container.shared.userSettings()
    settings.enableWriteProbe = true
    Container.shared.userSettings.reset()
    #expect(Container.shared.userSettings().enableWriteProbe)

    configure(.appStore)
    let (database, probe) = try probeDatabase()
    #expect(!probe.observes(eventsOfKind: .insert(tableName: "probeTest")))
    #expect(try write(database).isEmpty)
  }

  @Test("personal memory warning remains logged without an App Store popup")
  func appStoreMemoryWarning() async throws {
    configure(.appStore)
    let result = try await memoryWarning()
    #expect(!result.shown)
    #expect(result.logged)
  }

  @Test("losing eligibility before commit discards collected diagnostics")
  func distributionChangesDuringTransaction() throws {
    configure(.testFlight)
    Container.shared.userSettings().$enableWriteProbe.new(true)
    let (database, _) = try probeDatabase()

    let logs = try database.writeWithoutTransaction { db in
      try LogCapture.withSink { sink in
        try db.inTransaction {
          try db.execute(sql: "INSERT INTO probeTest DEFAULT VALUES")
          AppInfo.environment = .appStore
          return .commit
        }
        return sink.captured().filter { $0.label == "PodHaven/WriteProbe" }
      }
    }
    #expect(logs.isEmpty)

    AppInfo.environment = .testFlight
    let nextWrite = try write(database)
    #expect(nextWrite.contains { $0.message.contains("tables: probeTest, 1 row events") })
    #expect(nextWrite.contains { $0.message.contains("DB commit backtrace") })
  }

  @Test(
    "eligible environments retain live probe toggling",
    arguments: [EnvironmentType.iPhoneDev, .macDev, .simulator, .testFlight]
  )
  func liveProbeToggle(_ environment: EnvironmentType) throws {
    configure(environment)
    let (database, probe) = try probeDatabase()
    let settings = Container.shared.userSettings()
    #expect(!probe.observes(eventsOfKind: .insert(tableName: "probeTest")))
    #expect(try write(database).isEmpty)

    settings.enableWriteProbe = true
    #expect(probe.observes(eventsOfKind: .insert(tableName: "probeTest")))
    let logs = try write(database)
    #expect(logs.contains { $0.message.contains("tables: probeTest, 1 row events") })
    #expect(logs.contains { $0.message.contains("DB commit backtrace (sampled)") })

    settings.enableWriteProbe = false
    #expect(!probe.observes(eventsOfKind: .insert(tableName: "probeTest")))
    #expect(try write(database).isEmpty)
  }

  @Test(
    "eligible memory warning popup retains personal device restriction",
    arguments: [EnvironmentType.iPhoneDev, .macDev, .simulator, .testFlight],
    [true, false]
  )
  func eligibleMemoryWarning(_ environment: EnvironmentType, personalDevice: Bool) async throws {
    configure(environment, personalDevice: personalDevice)
    let result = try await memoryWarning()
    #expect(result.shown == personalDevice)
    #expect(result.logged)
  }

  @Test("delayed distribution detection keeps diagnostics off until TestFlight is confirmed")
  func delayedDetection() async throws {
    configure(.deployed)
    let settings = Container.shared.userSettings()
    settings.enableWriteProbe = true
    let (database, probe) = try probeDatabase()
    let requested = Broadcast(false)
    let (results, continuation) = AsyncStream<AppDistribution>.makeStream()
    Container.shared.appDistributor.register {
      {
        requested.new(true)
        for await result in results { return result }
        throw CancellationError()
      }
    }
    let detection = Task { await AppInfo.finalizeEnvironment() }
    defer { continuation.finish() }
    try await Wait.until {
      requested.value
    } _: {
      "Distribution lookup was not started"
    }

    #expect(AppInfo.environment == .deployed)
    #expect(!probe.observes(eventsOfKind: .insert(tableName: "probeTest")))
    #expect(try write(database).isEmpty)
    let unresolvedWarning = try await memoryWarning()
    #expect(!unresolvedWarning.shown)
    #expect(unresolvedWarning.logged)

    continuation.yield(.testFlight)
    await detection.value
    #expect(AppInfo.environment == .testFlight)
    #expect(probe.observes(eventsOfKind: .insert(tableName: "probeTest")))
    #expect(try write(database).contains { $0.message.contains("DB commit backtrace") })
    let confirmedWarning = try await memoryWarning()
    #expect(confirmedWarning.shown)
    #expect(confirmedWarning.logged)
  }

  @Test("failed distribution lookup keeps both diagnostics disabled")
  func failedDetection() async throws {
    configure(.deployed)
    let settings = Container.shared.userSettings()
    settings.enableWriteProbe = true
    let (database, probe) = try probeDatabase()
    Container.shared.appDistributor.register { { throw CocoaError(.fileReadUnknown) } }

    await AppInfo.finalizeEnvironment()

    #expect(AppInfo.environment == .appStore)
    #expect(!probe.observes(eventsOfKind: .insert(tableName: "probeTest")))
    #expect(try write(database).isEmpty)
    let result = try await memoryWarning()
    #expect(!result.shown)
    #expect(result.logged)
  }

  @Test(
    "non-TestFlight distribution channels keep diagnostics disabled",
    arguments: [AppDistribution.appStore, .marketplace("example"), .web, .other, .unknown]
  )
  func otherDistributionChannels(_ distribution: AppDistribution) async throws {
    configure(.deployed)
    Container.shared.appDistributor.register { { distribution } }
    await AppInfo.finalizeEnvironment()
    #expect(AppInfo.environment == .appStore)
    #expect(!AppInfo.environment.allowsDiagnostics)
    #expect(AppInfo.environment.isRelease)
  }

  @Test("Settings eligibility is observable when distribution detection completes")
  func settingsObservesDistributionChanges() {
    configure(.deployed)
    let changed = Broadcast(false)
    withObservationTracking {
      #expect(!AppInfo.environment.allowsDiagnostics)
      #expect(AppInfo.environment.isRelease)
    } onChange: {
      changed.new(true)
    }

    AppInfo.environment = .testFlight
    #expect(changed.value)
    #expect(AppInfo.environment.allowsDiagnostics)
    #expect(AppInfo.environment.isRelease)
  }

  @Test("disabled probes do not collect event timing")
  func disabledProbeDoesNotCollectTiming() throws {
    configure(.appStore)
    Container.shared.userSettings().$enableWriteProbe.new(true)
    let calls = ThreadSafe(0)
    let now = ContinuousClock().now
    Container.shared.continuousClockNow.register {
      {
        calls { $0 += 1 }
        return now
      }
    }
    let (database, _) = try probeDatabase()
    #expect(try write(database).isEmpty)
    #expect(calls() == 0)
  }
}
