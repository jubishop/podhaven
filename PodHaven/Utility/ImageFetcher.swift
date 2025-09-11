// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Nuke
import NukeUI
import SwiftUI

extension Container {
  var imageFetcher: Factory<any ImageFetchable> {
    Factory(self) { ImageFetcher() }.scope(.cached)
  }
}

struct ImageFetcher: ImageFetchable {
  private static let log = Log.as("ImageFetcher")

  fileprivate init() {}

  func fetch(_ url: URL) async throws -> UIImage {
    try await ImagePipeline.shared.image(for: url)
  }
}
