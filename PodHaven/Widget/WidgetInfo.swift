// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation

struct WidgetExtensionAcknowledgment: Codable, Equatable, Sendable {
  let buildNumber: String
  let latestTimelineRequestAt: Date
}

enum WidgetInfo {
  private static let extensionAcknowledgmentWrite = ThreadSafe(())

  // MARK: - Widget Kinds

  static let nowPlayingKind = "NowPlayingWidget"
  static let queueKind = "QueueWidget"
  static let nowPlayingQueueKind = "NowPlayingQueueWidget"
  static let lockScreenNowPlayingKind = "LockScreenNowPlayingWidget"
  static let playPauseControlKind = "PlayPauseControl"
  static let skipForwardControlKind = "SkipForwardControl"
  static let skipBackwardControlKind = "SkipBackwardControl"

  static let timelineKinds: Set<String> = [
    nowPlayingKind,
    queueKind,
    nowPlayingQueueKind,
    lockScreenNowPlayingKind,
  ]

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

  static var extensionAcknowledgmentURL: URL {
    containerURL.appendingPathComponent("widget-extension-acknowledgment.json")
  }

  static func recordExtensionTimelineRequest() throws -> WidgetExtensionAcknowledgment {
    try extensionAcknowledgmentWrite { _ in
      let acknowledgment = WidgetExtensionAcknowledgment(
        buildNumber: AppInfo.buildNumber,
        latestTimelineRequestAt: Container.shared.dateProvider().now
      )
      let data = try JSONEncoder().encode(acknowledgment)
      try Container.shared.fileManager()
        .writeDataSynchronously(
          data,
          to: extensionAcknowledgmentURL
        )
      return acknowledgment
    }
  }

  static func readExtensionAcknowledgment() throws -> WidgetExtensionAcknowledgment? {
    let fileManager = Container.shared.fileManager()
    guard fileManager.fileExists(at: extensionAcknowledgmentURL) else { return nil }
    let data = try fileManager.readDataSynchronously(from: extensionAcknowledgmentURL)
    return try JSONDecoder().decode(WidgetExtensionAcknowledgment.self, from: data)
  }
}
