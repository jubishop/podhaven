// Copyright Justin Bishop, 2026

import Accelerate
import Foundation

// Decone parameters for `NLContextualEmbedding` vectors. `mean` is the cone
// center; `principalComponents` are the next-most-dominant common directions,
// which empirically encode podcast *format* rather than topic — see
// `docs/research/embedding-model-alternatives.md`.
struct WhiteningTransform: Sendable {
  static let principalComponentCount = 3

  let mean: [Float]
  let principalComponents: [[Float]]

  // Center against `mean`, project out the first `k` PCs, re-normalize.
  // Zero-fills `destination` when the residual collapses (input lies in the
  // span of mean + top-k PCs) so cosine downstream lands at neutral.
  func apply(
    _ vector: UnsafeBufferPointer<Float>,
    strippingTopK k: Int,
    into destination: UnsafeMutableBufferPointer<Float>
  ) {
    guard mean.count == vector.count, destination.count == mean.count else {
      unsafe destination.update(repeating: 0)
      return
    }
    unsafe mean.withUnsafeBufferPointer { meanPtr in
      unsafe VectorMath.subtract(vector, meanPtr, into: destination)
    }
    let stripCount = min(max(k, 0), principalComponents.count)
    for component in principalComponents.prefix(stripCount)
    where component.count == vector.count {
      unsafe component.withUnsafeBufferPointer { componentPtr in
        let projection = unsafe VectorMath.dotProduct(
          UnsafeBufferPointer(destination),
          componentPtr
        )
        unsafe VectorMath.scaledAddInPlace(componentPtr, scalar: -projection, into: destination)
      }
    }
    let norm = unsafe VectorMath.normalizeInPlace(destination)
    if norm == 0 { unsafe destination.update(repeating: 0) }
  }
}
