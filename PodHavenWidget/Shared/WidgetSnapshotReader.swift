// Copyright Justin Bishop, 2026

import Foundation
import UIKit

enum WidgetSnapshotReader {
  static func read() -> WidgetSnapshot? {
    let url = WidgetConstants.snapshotURL

    guard FileManager.default.fileExists(atPath: url.path) else { return nil }

    do {
      let data = try Data(contentsOf: url)
      let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: data)

      guard snapshot.schemaVersion <= WidgetSnapshot.currentSchemaVersion else {
        return nil
      }

      return snapshot
    } catch {
      return nil
    }
  }

  static func decodeArtwork(from base64String: String?) -> UIImage? {
    guard let base64String else { return nil }
    guard let data = Data(base64Encoded: base64String) else { return nil }
    return UIImage(data: data)
  }
}
