#if DEBUG
// Copyright Justin Bishop, 2025

import Foundation
import UIKit
import FactoryKit

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
  static let allThumbnailNames = [
    "changelog-podcast",
    "changelog-interviews",
    "this-american-life-podcast",
    "this-american-life-episode1",
    "this-american-life-episode2",
    "pod-save-america-podcast",
    "pod-save-america-episode1",
    "pod-save-america-episode2",
  ]

  static let cachedImages = ThreadSafe<[String: UIImage]>([:])
  static let cachedImageData = ThreadSafe<[String: Data]>([:])

  // MARK: - Asset Loading

  static func loadAsset(named name: String, in folder: AssetFolder) -> Data {
    let namespacedName = buildNamespacedName(for: name, in: folder)

    guard let dataAsset = NSDataAsset(name: namespacedName, bundle: Bundle.main)
    else { fatalError("Could not load data asset: \(namespacedName) from main bundle") }

    return dataAsset.data
  }

  // MARK: - Image Loading

  static func loadAllThumbnails() -> [String: (url: URL, image: UIImage, data: Data)] {
    var allThumbnails: [String: (url: URL, image: UIImage, data: Data)] = [:]
    for thumbnailName in allThumbnailNames {
      let url = URL.valid()
      let image = loadImage(named: thumbnailName, in: .EpisodeThumbnails)
      let data = loadImageData(named: thumbnailName, in: .EpisodeThumbnails)
      Container.shared.fakeDataLoader().respond(to: url, data: data)
      allThumbnails[thumbnailName] = (url, image, data)
    }
    return allThumbnails
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
