// Copyright Justin Bishop, 2026

import CoreGraphics
import Foundation
import ImageIO
import UIKit

enum WidgetSnapshotReader {
  static func read() -> WidgetSnapshot? {
    let url = WidgetConstants.snapshotURL

    guard FileManager.default.fileExists(atPath: url.path) else {
      WidgetLog.warning("Snapshot file does not exist at \(url.path)")
      return nil
    }

    do {
      let data = try Data(contentsOf: url)
      WidgetLog.debug("Read snapshot file: \(data.count) bytes")

      let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: data)

      guard snapshot.schemaVersion <= WidgetSnapshot.currentSchemaVersion else {
        WidgetLog.warning(
          "Snapshot schema version \(snapshot.schemaVersion) is newer than supported \(WidgetSnapshot.currentSchemaVersion)"
        )
        return nil
      }

      WidgetLog.debug(
        "Decoded snapshot: nowPlaying=\(snapshot.nowPlaying != nil), queue=\(snapshot.queue.count) items, updatedAt=\(snapshot.updatedAt)"
      )
      return snapshot
    } catch {
      WidgetLog.error("Failed to decode snapshot: \(error)")
      return nil
    }
  }

  // Largest widget artwork is 80pt at 3x = 240px.
  private static let maxArtworkPixels = 240

  static func decodeArtwork(from base64String: String?) -> UIImage? {
    guard let base64String else { return nil }
    guard let data = Data(base64Encoded: base64String) else { return nil }
    return downsampledImage(from: data, maxPixels: maxArtworkPixels)
  }

  // Uses ImageIO to decode at a reduced size, avoiding the full-resolution
  // bitmap allocation that can OOM in the widget extension process.
  private static func downsampledImage(from data: Data, maxPixels: Int) -> UIImage? {
    let options: [CFString: Any] = [
      kCGImageSourceShouldCache: false
    ]
    guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary)
    else { return nil }

    let downsampleOptions: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixels,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
    ]

    guard
      let cgImage = CGImageSourceCreateThumbnailAtIndex(
        source,
        0,
        downsampleOptions as CFDictionary
      )
    else { return nil }

    return UIImage(cgImage: cgImage)
  }
}
