// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation

@testable import PodHaven

final class FakeWidgetCenter: WidgetReloading, Sendable {
  private struct ReloadAllCall: Sendable {
    let hadNowPlayingSnapshot: Bool
    let hadQueueSnapshot: Bool
  }

  private let reloadedKinds = ThreadSafe<[String]>([])
  private let reloadAllCalls = ThreadSafe<[ReloadAllCall]>([])
  private let placedWidgetKindsRequests = ThreadSafe(0)

  // Reports every widget kind as placed so reloadWidgets fans out to all
  // requested kinds, letting tests assert which kinds a given event reloads.
  private static let allKinds: Set<String> = [
    WidgetInfo.nowPlayingKind,
    WidgetInfo.queueKind,
    WidgetInfo.nowPlayingQueueKind,
    WidgetInfo.lockScreenNowPlayingKind,
    WidgetInfo.playPauseControlKind,
    WidgetInfo.skipForwardControlKind,
    WidgetInfo.skipBackwardControlKind,
  ]

  func placedWidgetKinds(
    _ completion: @escaping @Sendable (Result<Set<String>, any Error>) -> Void
  ) {
    placedWidgetKindsRequests { $0 += 1 }
    completion(.success(Self.allKinds))
  }

  func reloadTimelines(ofKind kind: String) {
    reloadedKinds { $0.append(kind) }
  }

  func reloadAllTimelines() {
    let fileManager = Container.shared.fileManager()
    reloadAllCalls {
      $0.append(
        ReloadAllCall(
          hadNowPlayingSnapshot: fileManager.fileExists(at: WidgetInfo.nowPlayingSnapshotURL),
          hadQueueSnapshot: fileManager.fileExists(at: WidgetInfo.queueSnapshotURL)
        )
      )
    }
  }

  // MARK: - Test Helpers

  func reloadCount(ofKind kind: String) -> Int {
    reloadedKinds().filter { $0 == kind }.count
  }

  func reloadAllCount() -> Int {
    reloadAllCalls().count
  }

  func everyReloadAllHadInitialSnapshots() -> Bool {
    reloadAllCalls().allSatisfy { $0.hadNowPlayingSnapshot && $0.hadQueueSnapshot }
  }

  func placedWidgetKindsRequestCount() -> Int {
    placedWidgetKindsRequests()
  }

  func reset() {
    reloadedKinds { $0.removeAll() }
    reloadAllCalls { $0.removeAll() }
    placedWidgetKindsRequests(0)
  }
}
