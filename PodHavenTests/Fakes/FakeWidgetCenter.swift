// Copyright Justin Bishop, 2026

import Foundation
import WidgetKit

@testable import PodHaven

final class FakeWidgetCenter: WidgetReloading, Sendable {
  private let configurations = ThreadSafe<[WidgetKit.WidgetInfo]>([])
  private let reloadedKinds = ThreadSafe<[String]>([])

  func getCurrentConfigurations(
    _ completion: @escaping @Sendable (Result<[WidgetKit.WidgetInfo], any Error>) -> Void
  ) {
    completion(.success(configurations()))
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
