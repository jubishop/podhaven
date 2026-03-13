// Copyright Justin Bishop, 2026

import Foundation
import Logging
import UIKit

enum WidgetSnapshotReader {
  private static let log = Log.as(LogSubsystem.Widget.snapshotReader)

  static func read() -> WidgetSnapshot? {
    let url = WidgetInfo.snapshotURL

    guard FileManager.default.fileExists(atPath: url.path) else {
      log.warning("Snapshot file does not exist at \(url.path)")
      return nil
    }

    let data: Data
    do {
      data = try Data(contentsOf: url)
    } catch {
      log.caughtError("Failed to read snapshot file at \(url.path)", error)
      return nil
    }

    log.debug("Read snapshot file: \(data.count) bytes")

    let snapshot: WidgetSnapshot
    do {
      snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
    } catch {
      log.caughtError("Failed to decode snapshot at \(url.path)", error)
      return nil
    }

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
  }

  static func decodeArtwork(from base64String: String?) -> UIImage? {
    guard let base64String else { return nil }

    guard let data = Data(base64Encoded: base64String) else {
      log.warning("Failed to decode base64 artwork string (\(base64String.count) chars)")
      return nil
    }

    guard let image = UIImage(data: data) else {
      log.warning("Failed to create UIImage from decoded artwork data (\(data.count) bytes)")
      return nil
    }

    return image
  }
}
