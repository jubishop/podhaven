// Copyright Justin Bishop, 2025

import Foundation

extension Array {
  subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
