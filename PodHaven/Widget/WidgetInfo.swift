// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation

struct WidgetExtensionAcknowledgment: Codable, Equatable, Sendable {
  let buildNumber: String
  let initializedAt: Date
  let latestTimelineRequestAt: Date?
}

struct WidgetExtensionTimelineRequestAcknowledgment: Equatable, Sendable {
  let buildNumber: String
  let timelineRequestAt: Date
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

  static let recentLogMaxFileSizeBytes = 32 * 1024
  static let recentLogTargetFileSizeBytes = recentLogMaxFileSizeBytes * 3 / 4

  static var recentLogFileURL: URL {
    containerURL.appendingPathComponent("recent-widget-log.ndjson")
  }

  static var extensionAcknowledgmentURL: URL {
    containerURL.appendingPathComponent("widget-extension-acknowledgment.json")
  }

  static func recordExtensionInitialization() throws -> WidgetExtensionAcknowledgment {
    try extensionAcknowledgmentWrite { _ in
      let buildNumber = AppInfo.buildNumber
      let latestTimelineRequestAt: Date?
      if let existing = try readExtensionAcknowledgment(), existing.buildNumber == buildNumber {
        latestTimelineRequestAt = existing.latestTimelineRequestAt
      } else {
        latestTimelineRequestAt = nil
      }
      let acknowledgment = WidgetExtensionAcknowledgment(
        buildNumber: buildNumber,
        initializedAt: Container.shared.dateProvider().now,
        latestTimelineRequestAt: latestTimelineRequestAt
      )
      try writeExtensionAcknowledgment(acknowledgment)
      return acknowledgment
    }
  }

  static func recordExtensionTimelineRequest() throws
    -> WidgetExtensionTimelineRequestAcknowledgment
  {
    try extensionAcknowledgmentWrite { _ in
      let buildNumber = AppInfo.buildNumber
      let timelineRequestAt = Container.shared.dateProvider().now
      let initializedAt: Date
      if let existing = try readExtensionAcknowledgment(), existing.buildNumber == buildNumber {
        initializedAt = existing.initializedAt
      } else {
        initializedAt = timelineRequestAt
      }
      let acknowledgment = WidgetExtensionAcknowledgment(
        buildNumber: buildNumber,
        initializedAt: initializedAt,
        latestTimelineRequestAt: timelineRequestAt
      )
      try writeExtensionAcknowledgment(acknowledgment)
      return WidgetExtensionTimelineRequestAcknowledgment(
        buildNumber: buildNumber,
        timelineRequestAt: timelineRequestAt
      )
    }
  }

  static func readExtensionAcknowledgment() throws -> WidgetExtensionAcknowledgment? {
    let fileManager = Container.shared.fileManager()
    guard fileManager.fileExists(at: extensionAcknowledgmentURL) else { return nil }
    let data = try fileManager.readDataSynchronously(from: extensionAcknowledgmentURL)
    return try JSONDecoder().decode(WidgetExtensionAcknowledgment.self, from: data)
  }

  private static func writeExtensionAcknowledgment(
    _ acknowledgment: WidgetExtensionAcknowledgment
  ) throws {
    let data = try JSONEncoder().encode(acknowledgment)
    try Container.shared.fileManager()
      .writeDataSynchronously(
        data,
        to: extensionAcknowledgmentURL
      )
  }
}
