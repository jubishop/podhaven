// Copyright Justin Bishop, 2026

import Foundation

protocol VectorStorable {
  var vector: Data { get }
  var dimension: Int { get }
}

extension VectorStorable {
  // Allocates a new [Float]. Prefer `withFloatBuffer` in hot paths.
  var floatVector: [Float] {
    unsafe withFloatBuffer { unsafe Array($0) }
  }

  // Zero-alloc view of the BLOB as a Float buffer. The pointer is only
  // valid inside `body` — never let it escape.
  func withFloatBuffer<R>(
    _ body: (UnsafeBufferPointer<Float>) throws -> R
  ) rethrows -> R {
    let floatStride = MemoryLayout<Float>.size
    let expected = dimension * floatStride
    guard vector.count == expected else {
      Assert.fatal(
        "vector blob length \(vector.count) does not match dimension \(dimension) * \(floatStride)"
      )
    }
    return try unsafe vector.withUnsafeBytes { bytes in
      let buffer = unsafe bytes.bindMemory(to: Float.self)
      return try unsafe body(buffer)
    }
  }

  static func vectorData(from floats: [Float]) -> Data {
    unsafe floats.withUnsafeBytes { unsafe Data($0) }
  }
}
