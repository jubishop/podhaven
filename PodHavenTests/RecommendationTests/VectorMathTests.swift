// Copyright Justin Bishop, 2026

import Foundation
import Testing

@testable import PodHaven

@Suite("VectorMath tests")
struct VectorMathTests {

  // MARK: - Normalize

  @Test("normalize produces unit vector")
  func normalizeUnit() {
    let vector: [Float] = [3.0, 4.0]
    let normalized = VectorMath.normalize(vector)
    let norm = sqrt(normalized.reduce(0) { $0 + $1 * $1 })
    #expect(abs(norm - 1.0) < 0.0001)
  }

  @Test("normalize handles zero vector gracefully")
  func normalizeZero() {
    let vector: [Float] = [0.0, 0.0, 0.0]
    let normalized = VectorMath.normalize(vector)
    #expect(normalized == [0.0, 0.0, 0.0])
  }

  @Test("normalize preserves direction")
  func normalizeDirection() {
    let vector: [Float] = [2.0, 0.0, 0.0]
    let normalized = VectorMath.normalize(vector)
    #expect(abs(normalized[0] - 1.0) < 0.0001)
    #expect(normalized[1] == 0.0)
    #expect(normalized[2] == 0.0)
  }

  // MARK: - Dot Product

  @Test("dotProduct computes correctly")
  func dotProductCorrect() {
    let v1: [Float] = [1.0, 2.0, 3.0]
    let v2: [Float] = [4.0, 5.0, 6.0]
    let result = VectorMath.dotProduct(v1, v2)
    #expect(abs(result - 32.0) < 0.0001)
  }

  @Test("dotProduct of orthogonal vectors is zero")
  func dotProductOrthogonal() {
    let v1: [Float] = [1.0, 0.0]
    let v2: [Float] = [0.0, 1.0]
    let result = VectorMath.dotProduct(v1, v2)
    #expect(result == 0.0)
  }

  @Test("dotProduct of identical unit vectors is one")
  func dotProductIdentical() {
    let v = VectorMath.normalize([1.0, 1.0, 1.0])
    let result = VectorMath.dotProduct(v, v)
    #expect(abs(result - 1.0) < 0.0001)
  }

  // MARK: - Weighted Average

  @Test("weightedAverage computes correctly")
  func weightedAverageCorrect() {
    let v1: [Float] = [1.0, 0.0]
    let v2: [Float] = [0.0, 1.0]
    let result = VectorMath.weightedAverage(v1, weight1: 0.6, v2, weight2: 0.4)
    #expect(abs(result[0] - 0.6) < 0.0001)
    #expect(abs(result[1] - 0.4) < 0.0001)
  }

  @Test("weightedAverage with equal weights averages components")
  func weightedAverageEqual() {
    let v1: [Float] = [2.0, 4.0]
    let v2: [Float] = [6.0, 8.0]
    let result = VectorMath.weightedAverage(v1, weight1: 0.5, v2, weight2: 0.5)
    #expect(abs(result[0] - 4.0) < 0.0001)
    #expect(abs(result[1] - 6.0) < 0.0001)
  }
}
