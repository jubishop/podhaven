// Copyright Justin Bishop, 2026

import SwiftUI
import Testing
import UIKit

@testable import PodHaven

@Suite("of long description rendering", .container)
@MainActor struct DescriptionRenderingTests {
  @Test("long episode descriptions visibly render at narrow width", arguments: [false, true])
  func longEpisodeDescriptionRenders(singleParagraph: Bool) async throws {
    let paragraph = "Visible description words with enough detail to fill the page. "
    let html =
      singleParagraph
      ? "<p>\(String(repeating: paragraph, count: 3100))</p>"
      : String(repeating: "<p>\(paragraph)\(paragraph)</p>", count: 1550)
    let episode = UnsavedPodcastEpisode(
      unsavedPodcast: try Create.unsavedPodcast(),
      unsavedEpisode: try Create.unsavedEpisode(description: html)
    )
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(episode))
    await viewModel.prepareDescription(font: .body)
    let scrollTarget = DescriptionScrollTarget()
    let host = TestHostingController(
      rootView: ScrollViewReader { proxy in
        ScrollView {
          EpisodeDetailView(viewModel: viewModel).descriptionView
            .padding()
        }
        .onAppear { scrollTarget.proxy = proxy }
      }
      .environment(\.dynamicTypeSize, .accessibility3)
      .environment(\.colorScheme, .light)
      .background(.white)
    )
    try await withHostedTestWindow(host, size: CGSize(width: 320, height: 640)) { window in
      let scroll = try #require(descendants(of: window).compactMap { $0 as? UIScrollView }.first)
      let proxy = try #require(scrollTarget.proxy)
      let last = viewModel.descriptionBlocks.count - 1
      for index in [0, last / 2, last] {
        let previousOffset = scroll.contentOffset
        proxy.scrollTo(index, anchor: index == last ? .bottom : .top)
        if index != 0 {
          try await Wait.until(
            { @MainActor in scroll.contentOffset != previousOffset },
            { "Expected scrolling to description block \(index)" }
          )
        }
        host.view.layoutIfNeeded()
        try await assertVisibleText(in: window, name: "description-block-\(index).png")
      }
      proxy.scrollTo(0, anchor: .top)
      host.view.layoutIfNeeded()

      if ProcessInfo.processInfo.isiOSAppOnMac {
        try await Wait.until(
          { @MainActor in
            host.view.layoutIfNeeded()
            return accessibilityElements(in: window)
              .contains {
                $0.accessibilityLabel?.contains("Visible") == true
              }
          },
          { "Expected the first description block in the accessibility tree" }
        )
        let text = accessibilityElements(in: window)
          .filter {
            $0.accessibilityLabel?.contains("Visible") == true
          }
        try #require(!text.isEmpty)
        #expect(
          text.allSatisfy { $0.accessibilityFrame.height < 16_384 },
          "Each rendered text surface must have a bounded height, found \(text.map { $0.accessibilityFrame.height })"
        )
      }
    }
  }

  private func assertVisibleText(in window: UIWindow, name: String) async throws {
    let png = try await Wait.forValue(maxAttempts: 100) { @MainActor in
      try visibleTextScreenshot(in: window)
    }
    Attachment.record(png, named: name)
  }

  private func visibleTextScreenshot(in window: UIWindow) throws -> Data? {
    window.layoutIfNeeded()
    let screenshot = UIGraphicsImageRenderer(bounds: window.bounds)
      .image { _ in
        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
      }
    let image = try #require(screenshot.cgImage)
    var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
    try pixels.withUnsafeMutableBytes { bytes in
      let context = try #require(
        CGContext(
          data: bytes.baseAddress,
          width: image.width,
          height: image.height,
          bitsPerComponent: 8,
          bytesPerRow: image.width * 4,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
      )
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    let darkPixels = stride(from: 0, to: pixels.count, by: 4)
      .filter {
        pixels[$0] < 100 && pixels[$0 + 1] < 100 && pixels[$0 + 2] < 100
      }
      .count
    guard darkPixels > 100 else { return nil }
    return screenshot.pngData()
  }

  private func descendants(of view: UIView) -> [UIView] {
    [view] + view.subviews.flatMap(descendants)
  }

}

@MainActor private final class DescriptionScrollTarget {
  var proxy: ScrollViewProxy?
}

@MainActor
private func accessibilityElements(in root: NSObject) -> [NSObject] {
  var visited: Set<ObjectIdentifier> = []
  func collect(_ object: NSObject) -> [NSObject] {
    guard visited.insert(ObjectIdentifier(object)).inserted else { return [] }
    var result = object.isAccessibilityElement ? [object] : []
    if let view = object as? UIView {
      result.append(contentsOf: view.subviews.flatMap(collect))
    }
    let count = object.accessibilityElementCount()
    if count != NSNotFound, count > 0 {
      for index in 0..<count {
        if let child = object.accessibilityElement(at: index) as? NSObject {
          result.append(contentsOf: collect(child))
        }
      }
    }
    return result
  }
  return collect(root)
}
