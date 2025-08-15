// Copyright Justin Bishop, 2025

import Foundation
import UIKit

enum TestBundle {
  static var bundle: Bundle {
    Bundle(for: TestBundleMarker.self)
  }

  static func loadDataAsset(named name: String) -> Data {
    // Try main bundle first (where Preview Assets.xcassets lives)
    if let dataAsset = NSDataAsset(name: name, bundle: Bundle.main) {
      return dataAsset.data
    }

    // Fallback to test bundle
    if let dataAsset = NSDataAsset(name: name, bundle: Bundle(for: TestBundleMarker.self)) {
      return dataAsset.data
    }

    fatalError("Could not load data asset: \(name) from main or test bundle")
  }

  static func loadDataAsset(named name: String, withExtension ext: String) -> Data {
    let namespacedName: String
    switch ext {
    case "rss":
      namespacedName = "rss/\(name)"
    case "json":
      namespacedName = "json/\(name)"
    case "opml":
      namespacedName = "opml/\(name)"
    default:
      namespacedName = name
    }
    return loadDataAsset(named: namespacedName)
  }

  static func createTempURL(forResource name: String, withExtension ext: String) -> URL {
    let data = loadDataAsset(named: name, withExtension: ext)
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(name).\(ext)")
    try! data.write(to: tempURL)
    return tempURL
  }
}

// Helper class to find the test bundle
private class TestBundleMarker {}
