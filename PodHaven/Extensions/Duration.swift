// Copyright Justin Bishop, 2025 

import Foundation

extension Duration {
  static func minutes(_ minutes: Int) -> Duration {
    seconds(minutes * 60)
  }
}
