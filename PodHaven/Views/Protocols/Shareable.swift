// Copyright Justin Bishop, 2026

import SwiftUI

@MainActor protocol Shareable: AnyObject {
  // MARK: - Required

  var shareTitle: String { get }
  var shareArtwork: UIImage? { get }
  var shareFallbackIcon: AppIcon { get }
  var shareURL: URL? { get }

  // MARK: - Provided by Default Implementation

  var sharePreview: SharePreview<Image, Image> { get }
  var sharePreviewImage: Image { get }
}

extension Shareable {
  var sharePreview: SharePreview<Image, Image> {
    SharePreview(
      Text(shareTitle),
      image: sharePreviewImage,
      icon: sharePreviewImage
    )
  }

  var sharePreviewImage: Image {
    guard let shareArtwork else { return shareFallbackIcon.rawImage }
    return Image(uiImage: shareArtwork)
  }
}
