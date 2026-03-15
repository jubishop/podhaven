// Copyright Justin Bishop, 2026

@testable import PodHaven

final class FakeControlCenter: ControlReloading, Sendable {
  private let reloadedKinds = ThreadSafe<[String]>([])

  func reloadControls(ofKind kind: String) {
    reloadedKinds { $0.append(kind) }
  }

  var allReloadedKinds: [String] {
    reloadedKinds()
  }

  func reloadCount(ofKind kind: String) -> Int {
    reloadedKinds().filter { $0 == kind }.count
  }

  func reset() {
    reloadedKinds { $0.removeAll() }
  }
}
