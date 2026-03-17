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
          maxFileSizeBytes: 600_000,
          targetFileSizeBytes: 400_000,
          writeSynchronously: { $0 >= .critical }
        ),
      ])
    }
    return Log.as(LogSubsystem.Widget.bundle)
  }()

  init() {
    Self.log.info("PodHavenWidgetBundle initialized")
  }

  var body: some Widget {
    NowPlayingWidget()
    QueueWidget()
    PodcastDetailWidget()
    LockScreenNowPlayingWidget()
    PlayPauseControl()
    SkipForwardControl()
    SkipBackwardControl()
  }
}
