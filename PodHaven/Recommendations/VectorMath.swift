// Copyright Justin Bishop, 2026

import Accelerate
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
    let scaled1 = vDSP.multiply(weight1, v1)
    let scaled2 = vDSP.multiply(weight2, v2)
    return vDSP.add(scaled1, scaled2)
  }

  static func normalize(_ vector: [Float]) -> [Float] {
    // Sum of squares == self-dot-product; reuse vDSP for both.
    let norm = sqrt(vDSP.dot(vector, vector))
    guard norm > 0 else { return vector }
    return vDSP.divide(vector, norm)
  }

  static func dotProduct(_ v1: [Float], _ v2: [Float]) -> Float {
    guard v1.count == v2.count else {
      Assert.fatal("Vector dimension mismatch: \(v1.count) vs \(v2.count)")
    }
    return vDSP.dot(v1, v2)
  }
}
