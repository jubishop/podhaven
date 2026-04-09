// Copyright Justin Bishop, 2026

import Foundation

enum VectorMath {
  static func weightedAverage(
    _ v1: [Float],
    weight1: Float,
    _ v2: [Float],
    weight2: Float
  ) -> [Float] {
    guard v1.count == v2.count else {
      Assert.fatal("Vector dimension mismatch: \(v1.count) vs \(v2.count)")
    }
    return zip(v1, v2).map { a, b in a * weight1 + b * weight2 }
  }

  static func normalize(_ vector: [Float]) -> [Float] {
    let norm = sqrt(vector.reduce(0) { $0 + $1 * $1 })
    guard norm > 0 else { return vector }
    return vector.map { $0 / norm }
  }

  static func dotProduct(_ v1: [Float], _ v2: [Float]) -> Float {
    guard v1.count == v2.count else {
      Assert.fatal("Vector dimension mismatch: \(v1.count) vs \(v2.count)")
    }
    return zip(v1, v2).reduce(0) { $0 + $1.0 * $1.1 }
  }
}
