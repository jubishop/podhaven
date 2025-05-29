// Copyright Justin Bishop, 2025

import Foundation
import Logging

enum LogKit {
  // MARK: - LogHandler Helpers

  private static let labelSeparator = "/"

  static func merge(
    handler: Logger.Metadata,
    provider: Logger.MetadataProvider?,
    oneOff: Logger.Metadata?
  ) -> Logger.Metadata {
    var merged = handler
    if let provider = provider { merged.merge(provider.get()) { (_, new) in new } }
    if let oneOff = oneOff { merged.merge(oneOff) { (_, new) in new } }
    return merged
  }

  static func destructureLabel(from label: String) -> (subsystem: String, category: String) {
    let parts = label.split(separator: labelSeparator, maxSplits: 1).map(String.init)
    Assert.precondition(parts.count == 2, "Invalid label format: \(label)")

    return (parts[0], parts[1])
  }

  // MARK: - Formatting Helpers

  static func buildLabel(subsystem: String, category: String) -> String {
    "\(subsystem)\(labelSeparator)\(category)"
  }
}
