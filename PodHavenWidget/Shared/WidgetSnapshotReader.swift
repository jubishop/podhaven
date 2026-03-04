// Copyright Justin Bishop, 2026

import Foundation
import Logging
import UIKit

enum WidgetSnapshotReader {
  private static let log = Logger(label: "PodHavenWidget/SnapshotReader")

  static func read() -> WidgetSnapshot? {
    let url = WidgetInfo.snapshotURL

    guard FileManager.default.fileExists(atPath: url.path) else {
      log.warning("Snapshot file does not exist at \(url.path)")
      return nil
    }

    do {
      let data = try Data(contentsOf: url)
      log.debug("Read snapshot file: \(data.count) bytes")

      let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: data)

      guard snapshot.schemaVersion <= WidgetSnapshot.currentSchemaVersion else {
        log.warning(
          """
          Snapshot schema version \
          \(snapshot.schemaVersion) is newer than \
          supported \(WidgetSnapshot.currentSchemaVersion)
          """
        )
        return nil
      }

      log.debug(
        """
        Decoded snapshot: \
        nowPlaying=\(snapshot.nowPlaying != nil), \
        queue=\(snapshot.queue.count) items, \
        updatedAt=\(snapshot.updatedAt)
        """
      )
      return snapshot
    } catch {
      log.error("Failed to decode snapshot: \(error)")
      return nil
    }
  }

  static func decodeArtwork(from base64String: String?) -> UIImage? {
    guard let base64String else { return nil }
    guard let data = Data(base64Encoded: base64String) else { return nil }
    return UIImage(data: data)
  }
}
