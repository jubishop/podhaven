// Copyright Justin Bishop, 2026

import Foundation

protocol VectorStorable {
  var vector: Data { get }
}

extension VectorStorable {
  var floatVector: [Float] {
    do {
      return try JSONDecoder().decode([Float].self, from: vector)
    } catch {
      Assert.fatal("Failed to decode embedding vector: \(error)")
    }
  }

  static func vectorData(from floats: [Float]) -> Data {
    do {
      return try JSONEncoder().encode(floats)
    } catch {
      Assert.fatal("Failed to encode embedding vector: \(error)")
    }
  }
}
