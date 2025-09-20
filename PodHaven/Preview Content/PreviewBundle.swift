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

struct PreviewBundle {
  static let cachedImages = ThreadSafe<[String: UIImage]>([:])
  static let cachedImageData = ThreadSafe<[String: Data]>([:])

  static func loadAsset(named name: String, in folder: AssetFolder) -> Data {
    let namespacedName = buildNamespacedName(for: name, in: folder)

    guard let dataAsset = NSDataAsset(name: namespacedName, bundle: Bundle.main)
    else { fatalError("Could not load data asset: \(namespacedName) from main bundle") }

    return dataAsset.data
  }

  static func loadImage(named name: String, in folder: ImageFolder) -> UIImage {
    let namespacedName = buildNamespacedName(for: name, in: folder)
    if let cachedImage = cachedImages[namespacedName] { return cachedImage }

    guard let uiImage = UIImage(named: namespacedName, in: Bundle.main, compatibleWith: nil)
    else { fatalError("Could not load image: \(namespacedName) from main bundle") }

    cachedImages[namespacedName] = uiImage
    return uiImage
  }

  static func loadImageData(named name: String, in folder: ImageFolder) -> Data {
    let namespacedName = buildNamespacedName(for: name, in: folder)
    if let cachedImageData = cachedImageData[namespacedName] { return cachedImageData }

    let uiImage = loadImage(named: name, in: folder)
    guard let data = uiImage.pngData()
    else { fatalError("Could not convert image to PNG data: \(name)") }

    cachedImageData[namespacedName] = data
    return data
  }

  private static func buildNamespacedName(for name: String, in folder: any RawRepresentable)
    -> String
  {
    "\(folder.rawValue)/\(name)"
  }
}
#endif
