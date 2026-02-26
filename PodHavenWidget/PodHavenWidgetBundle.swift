// Copyright Justin Bishop, 2026

import Logging
import SwiftUI
import WidgetKit

@main
struct PodHavenWidgetBundle: WidgetBundle {
  nonisolated private static let widgetWriter = NDJSONLogFileManager(
    fileURL: WidgetConstants.widgetLogFileURL,
    maxFileSizeBytes: 500_000,
    targetFileSizeBytes: 400_000
  )

  nonisolated private static let log: Logging.Logger = {
    LoggingSystem.bootstrap { label in
      MultiplexLogHandler([
        OSLogHandler(label: label),
        FileLogHandler(
          label: label,
          writeEntry: { level, entry in
            if level >= .critical {
              widgetWriter.writeSync(entry)
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
