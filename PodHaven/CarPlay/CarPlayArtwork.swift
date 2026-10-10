// Copyright Justin Bishop, 2026

import CarPlay
import Foundation
import Nuke

// CarPlay downsamples list images synchronously on the main thread, so rows
// receive thumbnails that the pipeline decodes in the background.
struct CarPlayArtwork {
  private static let fallbackScale: CGFloat = 3
  private let scale: CGFloat
  private let pixelSize: CGSize

  @MainActor init(displayScale: CGFloat) {
    scale = displayScale > 0 ? displayScale : Self.fallbackScale
    let bound = CPListItem.maximumImageSize
    pixelSize = CGSize(width: bound.width * scale, height: bound.height * scale)
  }

  func request(_ url: URL) -> ImageRequest {
    var request = ImageRequest(url: url)
    request.scale = scale
    request.thumbnail = ImageRequest.ThumbnailOptions(
      size: pixelSize,
      unit: .pixels,
      contentMode: .aspectFit
    )
    return request
  }
}
