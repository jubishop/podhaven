// Copyright Justin Bishop, 2024 

import Foundation

extension URL {
  static func valid() -> URL {
    return URL(string: "https://www.valid.com/\(String.random())")!
  }
}
