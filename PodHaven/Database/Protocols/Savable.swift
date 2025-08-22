// Copyright Justin Bishop, 2025

import Foundation
import GRDB

protocol Savable:
  Codable,
  Hashable,
  FetchableRecord,
  MutablePersistableRecord,
  Searchable,
  Sendable,
  Stringable
{}
