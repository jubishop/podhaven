// Copyright Justin Bishop, 2026

import CarPlay

@testable import PodHaven

@MainActor
final class FakeCarPlayInterfaceController: CarPlayInterfaceControlling {
  private(set) var roots: [CPTemplate] = []
  private(set) var completions: [(Bool, (any Error)?) -> Void] = []

  func setRootTemplate(
    _ rootTemplate: CPTemplate,
    animated: Bool,
    completion: ((Bool, (any Error)?) -> Void)?
  ) {
    roots.append(rootTemplate)
    if let completion { completions.append(completion) }
  }
}
