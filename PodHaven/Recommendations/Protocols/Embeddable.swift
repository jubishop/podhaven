// Copyright Justin Bishop, 2026

import Foundation

protocol Embeddable {
  var hasAvailableAssets: Bool { get }
  var revision: Int { get }
  func load() throws
  func requestAssets(completion: @escaping @Sendable ((any Error)?) -> Void)
  func embeddingResult(for string: String) throws -> any EmbeddableResult
}

protocol EmbeddableResult {
  func enumerateTokenVectors(
    in range: Range<String.Index>,
    using block: ([Double], Range<String.Index>) -> Bool
  )
}
