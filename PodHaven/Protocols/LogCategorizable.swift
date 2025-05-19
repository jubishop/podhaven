// Copyright Justin Bishop, 2025 

import Foundation

protocol LogCategorizable: RawRepresentable {
  var name: String { get }
  var level: LogLevel { get }
  var category: String { get }
}

extension LogCategorizable where Self: RawRepresentable, RawValue == String {
  var category: String { rawValue }
}
