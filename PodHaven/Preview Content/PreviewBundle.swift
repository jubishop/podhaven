#if DEBUG
// Copyright Justin Bishop, 2025

import Foundation
import UIKit

enum AssetFolder: String {
  case OPML
  case iTunesResults
  case FeedRSS
  case SearchResults
}

enum PreviewBundle {
  static func loadAsset(named name: String, in folder: AssetFolder) -> Data {
    let namespacedName = "\(folder.rawValue)/\(name)"

    guard let dataAsset = NSDataAsset(name: namespacedName, bundle: Bundle.main)
    else { fatalError("Could not load data asset: \(namespacedName) from main bundle") }

    return dataAsset.data
  }

  static func createURL(forAsset name: String, from folder: AssetFolder) -> URL {
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "\(name).\(folder.rawValue)"
    )

    if !FileManager.default.fileExists(atPath: tempURL.path) {
      let data = loadAsset(named: name, in: folder)
      try! data.write(to: tempURL)
    }

    return tempURL
  }
}
#endif
