// Copyright Justin Bishop, 2026

import Foundation
import Testing

@testable import PodHaven

@Suite("WhiteningTransform tests")
struct WhiteningTransformTests {

  // MARK: - apply()

  @Test("apply with no PCs centers and re-normalizes")
  func applyMeanOnly() {
    let transform = WhiteningTransform(
      mean: [0.5, 0.5, 0.5],
      principalComponents: []
    )
    let input: [Float] = [1.0, 0.5, 0.5]
    var dest = [Float](repeating: 0, count: 3)
    unsafe input.withUnsafeBufferPointer { inBuf in
      unsafe dest.withUnsafeMutableBufferPointer { destBuf in
        unsafe transform.apply(inBuf, strippingTopK: 0, into: destBuf)
      }
    }
    // input - mean = [0.5, 0, 0]; normalized = [1, 0, 0]
    #expect(abs(dest[0] - 1.0) < 0.0001)
    #expect(abs(dest[1]) < 0.0001)
    #expect(abs(dest[2]) < 0.0001)
  }

  @Test("apply with k=1 projects out the first PC")
  func applyStripsFirstPC() {
    // Mean is origin; PC is the x-axis. An input lying entirely on the x-axis
    // should collapse to zero (residual policy: caller sees zero vector).
    let transform = WhiteningTransform(
      mean: [0, 0, 0],
      principalComponents: [[1, 0, 0]]
    )
    let input: [Float] = [5.0, 0, 0]
    var dest = [Float](repeating: 0, count: 3)
    unsafe input.withUnsafeBufferPointer { inBuf in
      unsafe dest.withUnsafeMutableBufferPointer { destBuf in
        unsafe transform.apply(inBuf, strippingTopK: 1, into: destBuf)
      }
    }
    #expect(dest == [0, 0, 0])
  }

  @Test("apply preserves directions orthogonal to PCs")
  func applyKeepsOrthogonalDirections() {
    let transform = WhiteningTransform(
      mean: [0, 0, 0],
      principalComponents: [[1, 0, 0]]
    )
    let input: [Float] = [0.3, 0.0, 0.4]
    var dest = [Float](repeating: 0, count: 3)
    unsafe input.withUnsafeBufferPointer { inBuf in
      unsafe dest.withUnsafeMutableBufferPointer { destBuf in
        unsafe transform.apply(inBuf, strippingTopK: 1, into: destBuf)
      }
    }
    // x is stripped, residual = [0, 0, 0.4], normalized = [0, 0, 1]
    #expect(abs(dest[0]) < 0.0001)
    #expect(abs(dest[1]) < 0.0001)
    #expect(abs(dest[2] - 1.0) < 0.0001)
  }

  @Test("apply with mismatched destination size zeros the destination")
  func applyMismatchedDestZeroes() {
    let transform = WhiteningTransform(
      mean: [0, 0, 0],
      principalComponents: []
    )
    let input: [Float] = [1, 2, 3]
    var dest = [Float](repeating: 7, count: 5)  // wrong size
    unsafe input.withUnsafeBufferPointer { inBuf in
      unsafe dest.withUnsafeMutableBufferPointer { destBuf in
        unsafe transform.apply(inBuf, strippingTopK: 0, into: destBuf)
      }
    }
    #expect(dest == [0, 0, 0, 0, 0])
  }

  @Test("apply tolerates k > principalComponents.count")
  func applyOverflowsK() {
    let transform = WhiteningTransform(
      mean: [0, 0, 0],
      principalComponents: [[1, 0, 0]]
    )
    let input: [Float] = [0, 1, 0]
    var dest = [Float](repeating: 0, count: 3)
    unsafe input.withUnsafeBufferPointer { inBuf in
      unsafe dest.withUnsafeMutableBufferPointer { destBuf in
        // Asking for 5 PCs when only 1 exists should clamp to 1.
        unsafe transform.apply(inBuf, strippingTopK: 5, into: destBuf)
      }
    }
    // Orthogonal to the single PC, so passes through normalized: [0, 1, 0]
    #expect(abs(dest[0]) < 0.0001)
    #expect(abs(dest[1] - 1.0) < 0.0001)
    #expect(abs(dest[2]) < 0.0001)
  }
}
