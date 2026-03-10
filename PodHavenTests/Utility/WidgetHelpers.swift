// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation

@testable import PodHaven

@MainActor
enum WidgetHelpers {
  // MARK: - Dependency Access

  private static var fakeFileManager: FakeFileManager {
    Container.shared.fileManager() as! FakeFileManager
  }

  private static var sleeper: FakeSleeper {
    Container.shared.sleeper() as! FakeSleeper
  }

  // MARK: - Helpers

  static func waitForSnapshot() async throws {
    try await waitForSnapshot(where: { _ in true })
  }

  @discardableResult
  static func waitForSnapshot(
    where predicate: @Sendable (WidgetSnapshot) -> Bool
  ) async throws -> WidgetSnapshot {
    for _ in 0..<5 {
      try await sleeper.waitForSleepRequests(count: 1)
      await sleeper.advanceTime(by: .milliseconds(250))
      try await Wait.until(
        { [fakeFileManager] in fakeFileManager.fileExists(at: WidgetInfo.snapshotURL) },
        { "Snapshot file was never written" }
      )
      let snapshot = try await decodeSnapshot()
      if predicate(snapshot) { return snapshot }
    }
    throw TestError.waitUntilFailure("Snapshot never matched expected condition")
  }

  static func decodeSnapshot() async throws -> WidgetSnapshot {
    let data = try await fakeFileManager.readData(from: WidgetInfo.snapshotURL)
    return try JSONDecoder().decode(WidgetSnapshot.self, from: data)
  }
}
