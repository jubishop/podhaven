// Copyright Justin Bishop, 2026

import Foundation
import Logging
import OSLog
import Testing

@testable import PodHaven

@Suite("of OSLogHandler tests", .container)
struct OSLogHandlerTests {
  @Test("notice entries reach the unified log at its persisted notice level")
  func noticeEntriesKeepNoticeLevel() async throws {
    let subsystem = "PodHavenTests"
    let category = "OSLogHandlerTests-\(UUID().uuidString)"
    let logger = Logging.Logger(
      label: LogKit.buildLabel(subsystem: subsystem, category: category),
      factory: { OSLogHandler(label: $0) }
    )
    let start = Date().addingTimeInterval(-1)

    logger.notice("notice entry")
    // Error entries always persist, so seeing this one means the earlier entry
    // has been recorded if it was going to be.
    logger.error("sentinel entry")

    let levels = try await Wait.forValue(delay: .milliseconds(50)) { () -> [String: Int]? in
      let store = try OSLogStore(scope: .currentProcessIdentifier)
      let entries = try store.getEntries(
        at: store.position(date: start),
        matching: NSPredicate(format: "subsystem == %@ AND category == %@", subsystem, category)
      )
      var levels: [String: Int] = [:]
      for case let entry as OSLogEntryLog in entries {
        levels[entry.composedMessage] = entry.level.rawValue
      }
      return levels["sentinel entry"] == nil ? nil : levels
    }

    #expect(levels["notice entry"] == OSLogEntryLog.Level.notice.rawValue)
  }
}
