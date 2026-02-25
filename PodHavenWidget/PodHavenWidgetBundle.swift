// Copyright Justin Bishop, 2026

import Logging
import SwiftUI
import WidgetKit
import os

@main
struct PodHavenWidgetBundle: WidgetBundle {
  private static let widgetWriter = NDJSONLogFileManager(
    fileURL: WidgetConstants.widgetLogFileURL,
    maxFileSizeBytes: 500_000,
    targetFileSizeBytes: 400_000,
    queueLabel: "WidgetFileLog",
    onError: { error in
      os.Logger(subsystem: "PodHavenWidget", category: "FileLog")
        .error("Failed to write log: \(error.localizedDescription, privacy: .public)")
    },
    onTruncation: { orig, new in
      os.Logger(subsystem: "PodHavenWidget", category: "FileLog")
        .info("Log truncated from \(orig) to \(new) bytes")
    }
  )

  private static let log: Logging.Logger = {
    LoggingSystem.bootstrap { label in
      MultiplexLogHandler([
        OSLogHandler(label: label),
        FileLogHandler(
          label: label,
          writeEntry: { level, entry in
            if level >= .error {
              widgetWriter.writeSyncReporting(entry)
            } else {
              widgetWriter.writeAsync(entry)
            }
          }
        ),
      ])
    }
    return Logger(label: "PodHavenWidget/Widget")
  }()

  init() {
    Self.log.info("PodHavenWidgetBundle initialized")
  }

  var body: some Widget {
    NowPlayingWidget()
    QueueWidget()
  }
}
