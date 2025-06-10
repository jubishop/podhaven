// Copyright Justin Bishop, 2025

import Foundation
import Nuke
import SwiftUI

@testable import PodHaven

struct FakeImages: ImageFetchable {
  func prefetch(_ urls: [URL]) {}

  func fetchImage(_ url: URL) async throws -> UIImage {
    let hash = abs(url.absoluteString.hashValue)
    let size = CGSize(width: 100, height: 100)
    let color = UIColor(
      red: CGFloat((hash >> 16) & 0xFF) / 255.0,
      green: CGFloat((hash >> 8) & 0xFF) / 255.0,
      blue: CGFloat(hash & 0xFF) / 255.0,
      alpha: 1.0
    )

    return UIGraphicsImageRenderer(size: size).image { context in
        color.setFill()
        context.fill(CGRect(origin: .zero, size: size))
      }
  }
  
}
