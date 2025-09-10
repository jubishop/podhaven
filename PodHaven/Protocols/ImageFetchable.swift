// Copyright Justin Bishop, 2025

import Foundation
import NukeUI
import SwiftUI

protocol ImageFetchable: Sendable {
  func prefetch(_ urls: [URL]) async
  func fetch(_ url: URL) async throws -> UIImage
}
