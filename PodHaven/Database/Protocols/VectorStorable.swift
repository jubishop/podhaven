// Copyright Justin Bishop, 2026

import Foundation

protocol VectorStorable {
  var vector: Data { get }
  var dimension: Int { get }
}

extension VectorStorable {
  var floatVector: [Float] {
    let floatStride = MemoryLayout<Float>.size
    let expected = dimension * floatStride
    guard vector.count == expected else {
      Assert.fatal(
        "vector blob length \(vector.count) does not match dimension \(dimension) * \(floatStride)"
      )
    }
    return unsafe vector.withUnsafeBytes { unsafe Array($0.bindMemory(to: Float.self)) }
  }

  static func vectorData(from floats: [Float]) -> Data {
    unsafe floats.withUnsafeBytes { unsafe Data($0) }
  }
}
