// Copyright Justin Bishop, 2025

import Foundation
import Logging

protocol LogCategorizable: RawRepresentable, Sendable {
  var subsystem: String { get }
  var category: String { get }
  var level: Logger.Level { get }
}

extension LogCategorizable where Self: RawRepresentable, RawValue == String {
  var category: String { rawValue }
}
