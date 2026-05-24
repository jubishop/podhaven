// Copyright Justin Bishop, 2026

import Foundation

@testable import PodHaven

// Reference-type Embeddable for tests that need to flip asset availability
// after the embeddable has been handed to a `ContextualEmbedding`. The actor
// stores its embeddable in a `let`, so a struct copy can't be mutated — a
// class read through a `ThreadSafe` box can.
final class MutableEmbeddable: Embeddable, @unchecked Sendable {
  let revision: Int
  private let assetsAvailable: ThreadSafe<Bool>
  private let vectorFor: @Sendable (String) -> [Double]

  init(
    assetsAvailable: Bool,
    revision: Int = 1,
    vectorFor: @escaping @Sendable (String) -> [Double] = { _ in [1, 0, 0] }
  ) {
    self.assetsAvailable = ThreadSafe<Bool>(assetsAvailable)
    self.revision = revision
    self.vectorFor = vectorFor
  }

  var hasAvailableAssets: Bool { assetsAvailable() }

  func makeAssetsAvailable() { assetsAvailable(true) }

  func load() throws {}

  func requestAssets(completion: @escaping @Sendable ((any Error)?) -> Void) {
    completion(nil)
  }

  func embeddingResult(for string: String) throws -> any EmbeddableResult {
    FakeEmbeddingResult(vectors: [vectorFor(string)])
  }
}
