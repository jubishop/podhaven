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
          maxFileSizeBytes: 800_000,
          targetFileSizeBytes: 600_000,
          writeSynchronously: { $0 >= .critical }
        ),
      ])
    }
    return Log.as(LogSubsystem.Widget.bundle)
  }()

  init() {
    do {
      let acknowledgment = try WidgetInfo.recordExtensionTimelineRequest()
      Self.log.info(
        """
        PodHavenWidgetBundle initialized: extensionBuild=\(acknowledgment.buildNumber), \
        initialRequestAt=\(acknowledgment.latestTimelineRequestAt)
        """
      )
    } catch {
      Self.log.caughtError("Failed to persist extension initialization acknowledgment", error)
      Self.log.info("PodHavenWidgetBundle initialized without an acknowledgment")
    }
  }

  var body: some Widget {
    NowPlayingWidget()
    QueueWidget()
    NowPlayingQueueWidget()
    LockScreenNowPlayingWidget()
    PlayPauseControl()
    SkipForwardControl()
    SkipBackwardControl()
  }
}
