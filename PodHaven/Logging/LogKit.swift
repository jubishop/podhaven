// Copyright Justin Bishop, 2025 

import Foundation
import Logging

enum LogKit {
  // MARK: - LogHandler Helpers

  static func merge(
    handler: Logger.Metadata,
    provider: Logger.MetadataProvider?,
    oneOff: Logger.Metadata?
  ) -> Logger.Metadata {
    var merged = handler
    if let provider = provider {
      for (key, value) in provider.get() {
        merged[key] = value
      }
    }
    if let oneOff = oneOff {
      for (key, value) in oneOff {
        merged[key] = value
      }
    }
    return merged
  }

  // MARK: - Formatting Helpers
  
  static func fileName(from filePath: String) -> String {
    filePath.components(separatedBy: "/").suffix(2).joined(separator: "/")
  }
}
