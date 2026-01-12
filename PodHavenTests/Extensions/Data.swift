// Copyright Justin Bishop, 2025

import Foundation

extension Data {
  static func random(size: Int = 1024) -> Data {
    var data = Data(count: size)
    data.withUnsafeMutableBytes { bytes in
      arc4random_buf(bytes.baseAddress, size)
    }
    return data
  }
}
