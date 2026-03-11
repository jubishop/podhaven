// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Logging

enum WidgetInfo {

  // MARK: - Widget Kinds

  static let nowPlayingKind = "NowPlayingWidget"
  static let queueKind = "QueueWidget"
  static let lockScreenNowPlayingKind = "LockScreenNowPlayingWidget"

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

  static var snapshotURL: URL {
    containerURL.appendingPathComponent("widget-snapshot.json")
  }

  static var logFileURL: URL {
    containerURL.appendingPathComponent("widget-log.ndjson")
  }

  // MARK: - Playback Status

  private static let playbackStatusKey = "playbackStatus"

  private static let log = Logger(label: "WidgetInfo")

  static var playbackStatus: PlaybackStatus {
    get {
      guard let data = Container.shared.sharedDefaults().data(forKey: playbackStatusKey)
      else { return .stopped }

      do {
        return try JSONDecoder().decode(PlaybackStatus.self, from: data)
      } catch {
        log.error("Failed to decode playback status: \(error)")
        return .stopped
      }
    }
    set {
      do {
        let data = try JSONEncoder().encode(newValue)
        Container.shared.sharedDefaults().set(data, forKey: playbackStatusKey)
      } catch {
        log.error("Failed to encode playback status: \(error)")
      }
    }
  }
}
