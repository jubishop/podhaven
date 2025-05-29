// Copyright Justin Bishop, 2025

import Foundation
import Logging

protocol LogCategorizable: Sendable {
  var subsystem: String { get }
  var category: String { get }
  var level: Logger.Level { get }
}

extension LogCategorizable {
  var subsystem: String { String(describing: type(of: self)) }
  var level: Logger.Level { .info }
}

extension LogCategorizable where Self: RawRepresentable, RawValue == String {
  var category: String { rawValue }
}
