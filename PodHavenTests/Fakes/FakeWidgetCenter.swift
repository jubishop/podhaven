// Copyright Justin Bishop, 2026

import Foundation
import WidgetKit

@testable import PodHaven

final class FakeWidgetCenter: WidgetReloading, Sendable {
  private let configurations = ThreadSafe<[WidgetKit.WidgetInfo]>([])
  private let reloadedKinds = ThreadSafe<[String]>([])

  // Returns .failure by default so isWidgetPlaced falls through to the
  // safe default of true. Tests that need specific placement behavior
  // can set a custom result via configurationsResult.
  private let configurationsResult =
    ThreadSafe<Result<[WidgetKit.WidgetInfo], any Error>>(.failure(FakeError.notConfigured))

  private enum FakeError: Error { case notConfigured }

  func getCurrentConfigurations(
    _ completion: @escaping @Sendable (Result<[WidgetKit.WidgetInfo], any Error>) -> Void
  ) {
    completion(configurationsResult())
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
