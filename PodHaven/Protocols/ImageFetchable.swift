// Copyright Justin Bishop, 2025 

import Foundation
import SwiftUI

protocol ImageFetchable {
  func prefetch(_ urls: [URL]) async
  func fetch(_ url: URL) async throws -> UIImage
}
