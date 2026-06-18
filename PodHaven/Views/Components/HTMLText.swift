// Copyright Justin Bishop, 2025

import SwiftUI

// Renders a small HTML subset to a SwiftUI Text via HTMLContent's parser.
struct HTMLText: View {
  @Environment(\.font) private var environmentFont

  private let html: String

  init(_ html: String) {
    self.html = html
  }

  var body: some View {
    if let attributed = HTMLContent.attributedString(html: html, font: environmentFont ?? .body) {
      Text(attributed)
    } else {
      Text(html)
    }
  }
}

// MARK: - Previews

#if DEBUG
#Preview("HTMLText Gallery") {
  HTMLTextPreviewGallery()
}

#Preview("Description + Timestamps") {
  HTMLTextTimestampPreview()
}
#endif
