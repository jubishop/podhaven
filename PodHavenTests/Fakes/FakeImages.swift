// Copyright Justin Bishop, 2025

import Foundation
import Nuke
import SwiftUI

@testable import PodHaven

struct FakeImages: ImageFetchable {
  func prefetch(_ urls: [URL]) {}

  func fetchImage(_ url: URL) async throws -> UIImage {
    return UIImage()
  }
}
