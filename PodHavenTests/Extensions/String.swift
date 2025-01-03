// Copyright Justin Bishop, 2025

import Foundation

extension String {
  static func random(length: Int = 12) -> String {
    let characters =
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    let randomString = String(
      (0..<length).compactMap { _ in characters.randomElement() }
    )
    return randomString
  }
}
