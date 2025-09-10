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

enum ImageFolder: String {
  case EpisodeThumbnails
}

enum PreviewBundle {
  static func loadAsset(named name: String, in folder: AssetFolder) -> Data {
    let namespacedName = "\(folder.rawValue)/\(name)"

    guard let dataAsset = NSDataAsset(name: namespacedName, bundle: Bundle.main)
    else { fatalError("Could not load data asset: \(namespacedName) from main bundle") }

    return dataAsset.data
  }

  static func loadImage(named name: String, in folder: ImageFolder) -> UIImage {
    let namespacedName = "\(folder.rawValue)/\(name)"

    guard let uiImage = UIImage(named: namespacedName, in: Bundle.main, compatibleWith: nil)
    else { fatalError("Could not load image: \(namespacedName) from main bundle") }

    return uiImage
  }
}
#endif
