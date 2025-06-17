// Copyright Justin Bishop, 2025 

import Foundation
import SwiftUI

protocol ImageFetchable {
  func prefetch(_ urls: [URL])
  func fetchImage(_ url: URL) async throws -> UIImage
}
