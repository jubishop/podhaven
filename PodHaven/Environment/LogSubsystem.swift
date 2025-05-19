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

enum LogSubsystem {
  enum Search: String, LogCategorizable {
    case main

    var name: String { "search" }

    var level: LogLevel {
      switch self {
      case .main: return .debug
      }
    }
  }

  enum Database: String, LogCategorizable {
    case appDB

    var name: String { "database" }

    var level: LogLevel {
      switch self {
      case .appDB: return .info
      }
    }
  }

  enum Podcasts: String, LogCategorizable {
    case detail

    var name: String { "podcasts" }

    var level: LogLevel {
      switch self {
      case .detail: return .debug
      }
    }
  }
}
