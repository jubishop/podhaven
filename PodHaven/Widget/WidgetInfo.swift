// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation

enum WidgetInfo {

  // MARK: - Widget Kinds

  static let nowPlayingKind = "NowPlayingWidget"
  static let queueKind = "QueueWidget"

  // MARK: - Data Storage

  private static let appGroupID = "group.podhaven.shared"

  private static var containerURL: URL {
    let fileManager = Container.shared.fileManager()
    guard
      let containerURL = fileManager.containerURL(
        forSecurityApplicationGroupIdentifier: appGroupID
      )
    else {
      Assert.fatal("App group container not found for \(appGroupID)")
    }
    return containerURL
  }

  static var snapshotURL: URL {
    containerURL.appendingPathComponent("widget-snapshot.json")
  }

  static var logFileURL: URL {
    containerURL.appendingPathComponent("widget-log.ndjson")
  }
}
