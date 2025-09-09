// Copyright Justin Bishop, 2025

import Foundation
import NukeUI
import SwiftUI

protocol ImageFetchable: Sendable {
  func prefetch(_ urls: [URL]) async
  func fetch(_ url: URL) async throws -> UIImage

  @MainActor
  func lazyImage<Content: View>(
    _ url: URL?,
    @ViewBuilder content: @escaping (LazyImageState) -> Content
  ) -> LazyImage<Content>
}
