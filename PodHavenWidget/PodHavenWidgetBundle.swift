// Copyright Justin Bishop, 2026

import Logging
import SwiftUI
import WidgetKit

@main
struct PodHavenWidgetBundle: WidgetBundle {
  nonisolated private static let log: Logging.Logger = {
    LoggingSystem.bootstrap { label in
      MultiplexLogHandler([
        OSLogHandler(label: label),
        FileLogHandler(
          label: label,
          fileURL: WidgetInfo.logFileURL,
          maxFileSizeBytes: 500_000,
          targetFileSizeBytes: 400_000,
          writeSynchronously: { $0 >= .critical }
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
