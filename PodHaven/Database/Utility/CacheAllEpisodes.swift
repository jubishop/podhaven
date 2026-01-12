// Copyright Justin Bishop, 2025

import Foundation
import GRDB

enum CacheAllEpisodes: String, Codable, DatabaseValueConvertible {
  case never
  case cache
  case save
}
