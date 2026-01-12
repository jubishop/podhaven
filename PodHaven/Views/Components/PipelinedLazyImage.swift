// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Nuke
import NukeUI
import SwiftUI

struct PipelinedLazyImage<Content: View>: View {
  @DynamicInjected(\.imagePipeline) private var imagePipeline

  private let url: URL?
  private let content: (any LazyImageState) -> Content

  init(
    url: URL?,
    @ViewBuilder content: @escaping (any LazyImageState) -> Content
  ) {
    self.url = url
    self.content = content
  }

  var body: some View {
    LazyImage(url: url) { state in
      content(state)
    }
    .pipeline(imagePipeline)
  }
}
