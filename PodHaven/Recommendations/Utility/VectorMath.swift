// Copyright Justin Bishop, 2026

import Accelerate
import Foundation

enum VectorMath {
  // MARK: - Allocating helpers

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

  // MARK: - Zero-alloc buffer ops

  // Buffer-pointer overload — skips the `[Float]` boxing of `vDSP.dot`.
  static func dotProduct(
    _ a: UnsafeBufferPointer<Float>,
    _ b: UnsafeBufferPointer<Float>
  ) -> Float {
    var result: Float = 0
    unsafe vDSP_dotpr(
      a.baseAddress!,
      1,
      b.baseAddress!,
      1,
      &result,
      vDSP_Length(a.count)
    )
    return result
  }

  // dest += src. Both buffers must hold the same number of elements.
  static func addInPlace(
    _ src: UnsafeBufferPointer<Float>,
    into dest: UnsafeMutableBufferPointer<Float>
  ) {
    unsafe vDSP_vadd(
      src.baseAddress!,
      1,
      dest.baseAddress!,
      1,
      dest.baseAddress!,
      1,
      vDSP_Length(dest.count)
    )
  }

  // dest += scalar * src (a SAXPY). Both buffers must hold the same number
  // of elements.
  static func scaledAddInPlace(
    _ src: UnsafeBufferPointer<Float>,
    scalar: Float,
    into dest: UnsafeMutableBufferPointer<Float>
  ) {
    var scalar = scalar
    unsafe vDSP_vsma(
      src.baseAddress!,
      1,
      &scalar,
      dest.baseAddress!,
      1,
      dest.baseAddress!,
      1,
      vDSP_Length(dest.count)
    )
  }

  // dest = vector - subtraction. Allows aliasing dest with either input.
  static func subtract(
    _ vector: UnsafeBufferPointer<Float>,
    _ subtraction: UnsafeBufferPointer<Float>,
    into dest: UnsafeMutableBufferPointer<Float>
  ) {
    unsafe vDSP_vsub(
      subtraction.baseAddress!,
      1,
      vector.baseAddress!,
      1,
      dest.baseAddress!,
      1,
      vDSP_Length(dest.count)
    )
  }

  // dest /= scalar; aliases dest as both source and destination.
  static func divideInPlace(
    _ dest: UnsafeMutableBufferPointer<Float>,
    by scalar: Float
  ) {
    var scalar = scalar
    unsafe vDSP_vsdiv(
      dest.baseAddress!,
      1,
      &scalar,
      dest.baseAddress!,
      1,
      vDSP_Length(dest.count)
    )
  }

  // L2-normalize in place. Returns the prior norm so callers can detect
  // the zero-vector case (e.g. `WhiteningTransform.apply` zeroes the dest
  // on residual collapse).
  @discardableResult
  static func normalizeInPlace(_ dest: UnsafeMutableBufferPointer<Float>) -> Float {
    var normSq: Float = 0
    unsafe vDSP_dotpr(
      dest.baseAddress!,
      1,
      dest.baseAddress!,
      1,
      &normSq,
      vDSP_Length(dest.count)
    )
    let norm = sqrt(normSq)
    guard norm > 0 else { return 0 }
    unsafe divideInPlace(dest, by: norm)
    return norm
  }

  // dest = matrix * vector. `matrix` is `dim`×`dim`, vector and dest are `dim`.
  static func matrixVectorMultiply(
    _ matrix: UnsafeBufferPointer<Float>,
    _ vector: UnsafeBufferPointer<Float>,
    into dest: UnsafeMutableBufferPointer<Float>,
    dim: Int
  ) {
    unsafe vDSP_mmul(
      matrix.baseAddress!,
      1,
      vector.baseAddress!,
      1,
      dest.baseAddress!,
      1,
      vDSP_Length(dim),
      1,
      vDSP_Length(dim)
    )
  }

  // matrix += scalar * (vector ⊗ vectorᵀ). Two BLAS calls per row instead
  // of `dim` rank-1 updates: outer product into scratch, then a single
  // `dim²`-length SAXPY into matrix. Caller supplies the `dim²` scratch
  // so we don't allocate per call.
  static func accumulateScaledOuterProduct(
    of vector: UnsafeBufferPointer<Float>,
    scalar: Float,
    into matrix: UnsafeMutableBufferPointer<Float>,
    scratch: UnsafeMutableBufferPointer<Float>,
    dim: Int
  ) {
    unsafe vDSP_mmul(
      vector.baseAddress!,
      1,
      vector.baseAddress!,
      1,
      scratch.baseAddress!,
      1,
      vDSP_Length(dim),
      vDSP_Length(dim),
      1
    )
    var scalar = scalar
    unsafe vDSP_vsma(
      scratch.baseAddress!,
      1,
      &scalar,
      matrix.baseAddress!,
      1,
      matrix.baseAddress!,
      1,
      vDSP_Length(dim * dim)
    )
  }
}
