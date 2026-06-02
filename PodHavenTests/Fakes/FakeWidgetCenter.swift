// Copyright Justin Bishop, 2026

import Foundation

@testable import PodHaven

final class FakeWidgetCenter: WidgetReloading, Sendable {
  private let reloadedKinds = ThreadSafe<[String]>([])

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
    completion(.success(Self.allKinds))
  }

  func reloadTimelines(ofKind kind: String) {
    reloadedKinds { $0.append(kind) }
  }

  // MARK: - Test Helpers

  func reloadCount(ofKind kind: String) -> Int {
    reloadedKinds().filter { $0 == kind }.count
  }

  func reset() {
    reloadedKinds { $0.removeAll() }
  }
}
