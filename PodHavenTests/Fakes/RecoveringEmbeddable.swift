// Copyright Justin Bishop, 2026

import Foundation
import NaturalLanguage

@testable import PodHaven

final class RecoveringEmbeddable: Embeddable, Sendable {
  typealias Completion = @Sendable (NLContextualEmbedding.AssetsResult, (any Error)?) -> Void

  private struct State {
    var assetsAvailable: Bool
    var failuresRemaining: Int
    var loadCount = 0
    var requestCount = 0
    var vectorCount = 0
    var completions: [Completion] = []
  }

  let revision = 17
  private let state: ThreadSafe<State>
  let automaticResult: NLContextualEmbedding.AssetsResult?
  let requestError: (any Error)?

  static var compilationError: NSError {
    NSError(
      domain: "NLNaturalLanguageErrorDomain",
      code: 7,
      userInfo: [NSLocalizedDescriptionKey: "Embedding model requires compilation"]
    )
  }

  init(
    assetsAvailable: Bool = true,
    loadFailures: Int = 0,
    automaticResult: NLContextualEmbedding.AssetsResult? = nil,
    requestError: (any Error)? = nil
  ) {
    state = ThreadSafe(State(assetsAvailable: assetsAvailable, failuresRemaining: loadFailures))
    self.automaticResult = automaticResult
    self.requestError = requestError
  }

  var hasAvailableAssets: Bool { state { $0.assetsAvailable } }
  var loadCount: Int { state { $0.loadCount } }
  var requestCount: Int { state { $0.requestCount } }
  var vectorCount: Int { state { $0.vectorCount } }

  func load() throws {
    let fails = state { state in
      state.loadCount += 1
      guard state.failuresRemaining > 0 else { return false }
      state.failuresRemaining -= 1
      return true
    }
    if fails { throw Self.compilationError }
  }

  func requestAssets(completionHandler: @escaping Completion) {
    state {
      $0.requestCount += 1
      $0.completions.append(completionHandler)
    }
    if let automaticResult { completeNextRequest(automaticResult, error: requestError) }
  }

  @discardableResult
  func completeNextRequest(
    _ result: NLContextualEmbedding.AssetsResult,
    error: (any Error)? = nil
  ) -> Completion? {
    let completion = state { state -> Completion? in
      guard !state.completions.isEmpty else { return nil }
      if result == .available, error == nil { state.assetsAvailable = true }
      return state.completions.removeFirst()
    }
    completion?(result, error)
    return completion
  }

  func embeddingResult(for string: String) throws -> any EmbeddableResult {
    state { $0.vectorCount += 1 }
    return FakeEmbeddingResult(vectors: [[1, 0, 0]])
  }
}
