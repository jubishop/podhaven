// Copyright Justin Bishop, 2026

import Foundation

enum WidgetConstants {
  static let appGroupID = "group.podhaven.shared"
  static let snapshotFilename = "widget-snapshot.json"

  static let nowPlayingKind = "NowPlayingWidget"
  static let queueKind = "QueueWidget"

  static var snapshotURL: URL {
    guard
      let containerURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: appGroupID
      )
    else {
      // Assert is unavailable in the widget target; fatalError directly
      // since a missing app group is an unrecoverable configuration error.
      fatalError("App group container not found for \(appGroupID)")
    }
    return containerURL.appendingPathComponent(snapshotFilename)
  }
}
