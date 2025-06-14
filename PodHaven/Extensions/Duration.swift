// Copyright Justin Bishop, 2025

import Foundation

extension Duration {
  static func minutes(_ minutes: Int) -> Duration {
    seconds(minutes * 60)
  }

  static func hours(_ hours: Int) -> Duration {
    minutes(hours * 60)
  }
}
