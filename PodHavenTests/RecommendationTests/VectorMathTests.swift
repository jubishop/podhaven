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

  // MARK: - In-place buffer ops

  @Test("addInPlace sums into destination")
  func addInPlaceCorrect() {
    var dest: [Float] = [1.0, 2.0, 3.0]
    let src: [Float] = [10.0, 20.0, 30.0]
    unsafe src.withUnsafeBufferPointer { srcBuf in
      unsafe dest.withUnsafeMutableBufferPointer { destBuf in
        unsafe VectorMath.addInPlace(srcBuf, into: destBuf)
      }
    }
    #expect(dest == [11.0, 22.0, 33.0])
  }

  @Test("scaledAddInPlace implements SAXPY")
  func scaledAddInPlaceCorrect() {
    var dest: [Float] = [1.0, 2.0, 3.0]
    let src: [Float] = [10.0, 20.0, 30.0]
    unsafe src.withUnsafeBufferPointer { srcBuf in
      unsafe dest.withUnsafeMutableBufferPointer { destBuf in
        unsafe VectorMath.scaledAddInPlace(srcBuf, scalar: 0.5, into: destBuf)
      }
    }
    #expect(dest == [6.0, 12.0, 18.0])
  }

  @Test("subtract writes vector - subtraction into destination")
  func subtractCorrect() {
    let vector: [Float] = [10.0, 20.0, 30.0]
    let subtraction: [Float] = [1.0, 2.0, 3.0]
    var dest = [Float](repeating: 0, count: 3)
    unsafe vector.withUnsafeBufferPointer { vecBuf in
      unsafe subtraction.withUnsafeBufferPointer { subBuf in
        unsafe dest.withUnsafeMutableBufferPointer { destBuf in
          unsafe VectorMath.subtract(vecBuf, subBuf, into: destBuf)
        }
      }
    }
    #expect(dest == [9.0, 18.0, 27.0])
  }

  @Test("normalizeInPlace scales to unit length and returns prior norm")
  func normalizeInPlaceCorrect() {
    var dest: [Float] = [3.0, 4.0]
    let norm = unsafe dest.withUnsafeMutableBufferPointer { destBuf in
      unsafe VectorMath.normalizeInPlace(destBuf)
    }
    #expect(abs(norm - 5.0) < 0.0001)
    #expect(abs(dest[0] - 0.6) < 0.0001)
    #expect(abs(dest[1] - 0.8) < 0.0001)
  }

  @Test("normalizeInPlace returns 0 for zero vector")
  func normalizeInPlaceZero() {
    var dest: [Float] = [0.0, 0.0, 0.0]
    let norm = unsafe dest.withUnsafeMutableBufferPointer { destBuf in
      unsafe VectorMath.normalizeInPlace(destBuf)
    }
    #expect(norm == 0)
    #expect(dest == [0.0, 0.0, 0.0])
  }

  @Test("matrixVectorMultiply matches manual dot products")
  func matrixVectorMultiplyCorrect() {
    // 3x3 identity-like matrix with a known shape:
    //   [1 2 3]   [1]   [14]
    //   [4 5 6] * [2] = [32]
    //   [7 8 9]   [3]   [50]
    let matrix: [Float] = [1, 2, 3, 4, 5, 6, 7, 8, 9]
    let vector: [Float] = [1, 2, 3]
    var dest = [Float](repeating: 0, count: 3)
    unsafe matrix.withUnsafeBufferPointer { matBuf in
      unsafe vector.withUnsafeBufferPointer { vecBuf in
        unsafe dest.withUnsafeMutableBufferPointer { destBuf in
          unsafe VectorMath.matrixVectorMultiply(matBuf, vecBuf, into: destBuf, dim: 3)
        }
      }
    }
    #expect(abs(dest[0] - 14) < 0.0001)
    #expect(abs(dest[1] - 32) < 0.0001)
    #expect(abs(dest[2] - 50) < 0.0001)
  }

  @Test("accumulateScaledOuterProduct adds scalar * v⊗vᵀ in place")
  func accumulateScaledOuterProductCorrect() {
    // v = [1, 2, 3], scalar = 2
    // v⊗vᵀ = [[1,2,3],[2,4,6],[3,6,9]]
    // 2 * v⊗vᵀ = [[2,4,6],[4,8,12],[6,12,18]]
    let v: [Float] = [1, 2, 3]
    var matrix = [Float](repeating: 0, count: 9)
    var scratch = [Float](repeating: 0, count: 9)
    unsafe v.withUnsafeBufferPointer { vBuf in
      unsafe matrix.withUnsafeMutableBufferPointer { matBuf in
        unsafe scratch.withUnsafeMutableBufferPointer { scratchBuf in
          unsafe VectorMath.accumulateScaledOuterProduct(
            of: vBuf,
            scalar: 2,
            into: matBuf,
            scratch: scratchBuf,
            dim: 3
          )
        }
      }
    }
    let expected: [Float] = [2, 4, 6, 4, 8, 12, 6, 12, 18]
    for (i, x) in matrix.enumerated() {
      #expect(abs(x - expected[i]) < 0.0001)
    }
  }

  // MARK: - Buffer-pointer dot product parity

  @Test("buffer-pointer dotProduct matches [Float] overload")
  func dotProductBufferParity() {
    let a: [Float] = [1.5, 2.5, -3.0]
    let b: [Float] = [4.0, 0.5, 6.0]
    let viaArray = VectorMath.dotProduct(a, b)
    let viaBuffer = unsafe a.withUnsafeBufferPointer { aBuf in
      unsafe b.withUnsafeBufferPointer { bBuf in
        unsafe VectorMath.dotProduct(aBuf, bBuf)
      }
    }
    #expect(abs(viaArray - viaBuffer) < 0.0001)
  }
}
