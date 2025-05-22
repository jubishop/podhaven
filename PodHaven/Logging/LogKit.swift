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
      merged.merge(provider.get()) { (_, new) in new }
    }
    if let oneOff = oneOff {
      merged.merge(oneOff) { (_, new) in new }
    }

    return merged
  }

  // MARK: - Formatting Helpers

}
