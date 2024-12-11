// Copyright Justin Bishop, 2024

import Foundation
import GRDB

extension DerivableRequest {
  func shuffled() -> Self {
    order(sql: "RANDOM()")
  }
}
