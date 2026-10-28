// Copyright Justin Bishop, 2026

import SwiftUI
import Testing
import UIKit

@testable import PodHaven

@Suite("of toolbar icon color tests", .container)
@MainActor struct ToolbarIconColorTests {
  @Test("episode toolbar menus retain their icon colors", arguments: [ColorScheme.light, .dark])
  func toolbarMenusRetainTheirIconColor(appearance: ColorScheme) async throws {
    let episode = UnsavedPodcastEpisode(
      unsavedPodcast: try Create.unsavedPodcast(),
      unsavedEpisode: try Create.unsavedEpisode(rating: .loved)
    )
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(episode))
    let host = TestHostingController(
      rootView: NavigationStack {
        EpisodeDetailView(viewModel: viewModel)
      }
      .environment(\.colorScheme, appearance)
    )
    host.overrideUserInterfaceStyle = appearance == .dark ? .dark : .light
    host.traitOverrides.activeAppearance = .active
    try await withHostedTestWindow(host) { window in
      try await Wait.until(
        { @MainActor in
          Self.descendants(of: window).contains { $0 is UINavigationBar }
        },
        { "Navigation bar did not appear" }
      )
      let navigationBar = try #require(
        Self.descendants(of: window).first { $0 is UINavigationBar }
      )
      let screenshot = UIGraphicsImageRenderer(bounds: window.bounds)
        .image { _ in
          _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
      Attachment.record(try #require(screenshot.pngData()), named: "episode-toolbar.png")
      for icon in [AppIcon.playButton, .rating(for: .loved)] {
        let expectedColor = UIColor(icon.color(for: appearance))
        let iconName = icon.text
        try await Wait.until(
          { @MainActor in
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            let frame = navigationBar.convert(navigationBar.bounds, to: window)
            return Self.contains(expectedColor, in: frame, rendering: window)
          },
          { "Toolbar menu did not render its icon color: \(iconName), \(appearance)" }
        )
      }
    }
  }

  private static func descendants(of view: UIView) -> [UIView] {
    [view] + view.subviews.flatMap(descendants)
  }

  private static func contains(_ color: UIColor, in rect: CGRect, rendering view: UIView) -> Bool {
    let width = Int(view.bounds.width.rounded(.up))
    let height = Int(view.bounds.height.rounded(.up))
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let rendered = pixels.withUnsafeMutableBytes { bytes in
      guard
        let context = CGContext(
          data: bytes.baseAddress,
          width: width,
          height: height,
          bitsPerComponent: 8,
          bytesPerRow: width * 4,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        )
      else { return false }

      context.translateBy(x: 0, y: CGFloat(height))
      context.scaleBy(x: 1, y: -1)
      UIGraphicsPushContext(context)
      defer { UIGraphicsPopContext() }
      return view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
    }
    guard rendered else { return false }

    var expectedRed: CGFloat = 0
    var expectedGreen: CGFloat = 0
    var expectedBlue: CGFloat = 0
    var expectedAlpha: CGFloat = 0
    guard
      color.resolvedColor(with: view.traitCollection)
        .getRed(
          &expectedRed,
          green: &expectedGreen,
          blue: &expectedBlue,
          alpha: &expectedAlpha
        )
    else { return false }

    let minX = max(0, Int(rect.minX.rounded(.down)))
    let maxX = min(width, Int(rect.maxX.rounded(.up)))
    let minY = max(0, Int(rect.minY.rounded(.down)))
    let maxY = min(height, Int(rect.maxY.rounded(.up)))
    let tolerance = 0.2
    var matchingPixelCount = 0

    for y in minY..<maxY {
      for x in minX..<maxX {
        let offset = (y * width + x) * 4
        let red = CGFloat(pixels[offset]) / 255
        let green = CGFloat(pixels[offset + 1]) / 255
        let blue = CGFloat(pixels[offset + 2]) / 255
        if abs(red - expectedRed) < tolerance,
          abs(green - expectedGreen) < tolerance,
          abs(blue - expectedBlue) < tolerance
        {
          matchingPixelCount += 1
        }
      }
    }
    return matchingPixelCount >= 8
  }
}
