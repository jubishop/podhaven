// Copyright Justin Bishop, 2025

import Foundation
import GRDB

enum QueueAllEpisodes: String, Codable, DatabaseValueConvertible {
  case never
  case onBottom
  case onTop
}
