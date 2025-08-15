#if DEBUG
// Copyright Justin Bishop, 2025

import Foundation
import UIKit

enum PreviewBundle {
  static func loadAsset(named name: String, withExtension ext: String) -> Data {
    let namespacedName = "\(ext)/\(name)"

    guard let dataAsset = NSDataAsset(name: namespacedName, bundle: Bundle.main)
    else { fatalError("Could not load data asset: \(namespacedName) from main bundle") }

    return dataAsset.data
  }

  static func createURL(forResource name: String, withExtension ext: String) -> URL {
    let data = loadAsset(named: name, withExtension: ext)
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).\(ext)")
    try! data.write(to: tempURL)
    return tempURL
  }
}
#endif
