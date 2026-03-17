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

  // Waits for debounce sleep cycles, then polls for the snapshot file.
  // Multiple independent debounces may be active, so we tolerate iterations
  // where a different debounce fires before the one we're waiting for.
  @discardableResult
  static func waitForDebounced<T: WidgetSnapshotType>(
    _ type: T.Type,
    url: URL,
    where predicate: @escaping @Sendable (T) -> Bool = { _ in true }
  ) async throws -> T {
    for _ in 0..<10 {
      try await sleeper.waitForSleepRequests(count: 1)
      await sleeper.advanceTime(by: .milliseconds(250))

      // Wait.until polls with real Task.sleep, giving async write work time
      // to complete after advanceTime resumes the debounce continuation.
      // Wrap in do/catch so we can try the next debounce cycle if the file
      // wasn't written by this particular debounce.
      do {
        try await Wait.until(
          maxAttempts: 50,
          { [fakeFileManager] in
            guard fakeFileManager.fileExists(at: url) else { return false }
            let data = try await fakeFileManager.readData(from: url)
            let snapshot = try JSONDecoder().decode(T.self, from: data)
            return predicate(snapshot)
          },
          { "Snapshot at \(url.lastPathComponent) not ready yet" }
        )
        let data = try await fakeFileManager.readData(from: url)
        return try JSONDecoder().decode(T.self, from: data)
      } catch {
        continue
      }
    }
    throw TestError.waitUntilFailure(
      "Snapshot at \(url.lastPathComponent) never matched expected condition"
    )
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
