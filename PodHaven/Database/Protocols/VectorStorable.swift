// Copyright Justin Bishop, 2026

import Foundation

protocol VectorStorable {
  var vector: Data { get }
}

extension VectorStorable {
  var floatVector: [Float] {
    unsafe vector.withUnsafeBytes { unsafe Array($0.bindMemory(to: Float.self)) }
  }

  static func vectorData(from floats: [Float]) -> Data {
    unsafe floats.withUnsafeBytes { unsafe Data($0) }
  }
}
