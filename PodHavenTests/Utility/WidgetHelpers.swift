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

  // MARK: - Debounced Helper

  // Drives any pending fake-sleeper debounces forward in 250ms ticks and polls
  // for the snapshot file in between. Wait.until's 10ms cadence gives the
  // debounce action's async work (image pipeline, encoding, file write) time
  // to complete after the debounce fires. The 5s overall budget is generous
  // enough to ride out CI-stress slowdowns in the snapshot writer's TaskGroup.
  @discardableResult
  static func waitForDebounced<T: WidgetSnapshotType>(
    _ type: T.Type,
    url: URL,
    where predicate: @escaping @Sendable (T) -> Bool = { _ in true }
  ) async throws -> T {
    try await Wait.until(
      maxAttempts: 500,
      { [sleeper, fakeFileManager] in
        if sleeper.pendingCount() > 0 {
          await sleeper.advanceTime(by: .milliseconds(250))
        }
        guard fakeFileManager.fileExists(at: url) else { return false }
        let data = try await fakeFileManager.readData(from: url)
        let snapshot = try JSONDecoder().decode(T.self, from: data)
        return predicate(snapshot)
      },
      { "Snapshot at \(url.lastPathComponent) never matched expected condition" }
    )
    let data = try await fakeFileManager.readData(from: url)
    return try JSONDecoder().decode(T.self, from: data)
  }

  // MARK: - Per-Type Convenience

  @discardableResult
  static func waitForNowPlayingSnapshot(
    where predicate: @escaping @Sendable (NowPlayingSnapshot) -> Bool = { _ in true }
  ) async throws -> NowPlayingSnapshot {
    try await waitForDebounced(
      NowPlayingSnapshot.self,
      url: WidgetInfo.nowPlayingSnapshotURL,
      where: predicate
    )
  }

  @discardableResult
  static func waitForQueueSnapshot(
    where predicate: @escaping @Sendable (QueueSnapshot) -> Bool = { _ in true }
  ) async throws -> QueueSnapshot {
    try await waitForDebounced(
      QueueSnapshot.self,
      url: WidgetInfo.queueSnapshotURL,
      where: predicate
    )
  }

}
