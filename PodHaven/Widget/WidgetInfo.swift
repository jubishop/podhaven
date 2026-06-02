// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation

enum WidgetInfo {

  // MARK: - Widget Kinds

  static let nowPlayingKind = "NowPlayingWidget"
  static let queueKind = "QueueWidget"
  static let nowPlayingQueueKind = "NowPlayingQueueWidget"
  static let lockScreenNowPlayingKind = "LockScreenNowPlayingWidget"
  static let playPauseControlKind = "PlayPauseControl"
  static let skipForwardControlKind = "SkipForwardControl"
  static let skipBackwardControlKind = "SkipBackwardControl"

  // MARK: - Data Storage

  private static var containerURL: URL {
    let fileManager = Container.shared.fileManager()
    guard
      let containerURL = fileManager.containerURL(
        forSecurityApplicationGroupIdentifier: AppInfo.appGroupID
      )
    else {
      Assert.fatal("App group container not found for \(AppInfo.appGroupID)")
    }
    return containerURL
  }

  static var nowPlayingSnapshotURL: URL {
    containerURL.appendingPathComponent("widget-now-playing.json")
  }

  static var queueSnapshotURL: URL {
    containerURL.appendingPathComponent("widget-queue.json")
  }

  static var logFileURL: URL {
    containerURL.appendingPathComponent("widget-log.ndjson")
  }
}
