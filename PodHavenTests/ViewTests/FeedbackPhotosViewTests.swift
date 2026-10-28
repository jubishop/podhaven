// Copyright Justin Bishop, 2026

import SwiftUI
import Testing
import UIKit

@testable import PodHaven

@Suite("of feedback photo layout tests", .container)
@MainActor struct FeedbackPhotosViewTests {
  @Test(
    "photos keep their aspect ratios in one bounded horizontal row",
    .enabled(if: ProcessInfo.processInfo.isiOSAppOnMac),
    arguments: [1, 2, 5],
    [DynamicTypeSize.large, .accessibility5]
  )
  func horizontalLayout(count: Int, dynamicTypeSize: DynamicTypeSize) async throws {
    let sizes = (0..<count)
      .map { index in
        index.isMultiple(of: 2)
          ? CGSize(width: 100, height: 200) : CGSize(width: 200, height: 100)
      }
    let photos = try sizes.map(Self.photoData)
    let host = TestHostingController(
      rootView: Form {
        Section("Photos") {
          FeedbackPhotosView(photos: photos)
        }
      }
      .dynamicTypeSize(dynamicTypeSize)
    )
    try await withHostedTestWindow(host, size: CGSize(width: 700, height: 844)) { window in
      let row = try await Self.waitForPhotoRow(in: window)
      let screenshot = UIGraphicsImageRenderer(bounds: window.bounds)
        .image { _ in
          window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
      Attachment.record(
        try #require(screenshot.pngData()),
        named: "feedback-photos-\(count)-\(dynamicTypeSize).png"
      )
      let photoWidths = sizes.map { $0.width / $0.height * 200 }.reduce(0, +)
      #expect(abs(row.contentSize.height - 200) < 1)
      #expect(abs(row.contentSize.width - (photoWidths + CGFloat(count - 1) * 12)) < 1)
    }
  }

  @Test(
    "overflowing photos scroll in both directions without moving the form",
    .enabled(if: ProcessInfo.processInfo.isiOSAppOnMac),
    arguments: [DynamicTypeSize.large, .accessibility5]
  )
  func scrolling(dynamicTypeSize: DynamicTypeSize) async throws {
    let photos = try (0..<5).map { _ in try Self.photoData(CGSize(width: 100, height: 200)) }
    let host = TestHostingController(
      rootView: Form {
        Section("Photos") {
          FeedbackPhotosView(photos: photos)
        }
        Section {
          ForEach(0..<20) { index in
            Text("Form row \(index)")
          }
        }
      }
      .dynamicTypeSize(dynamicTypeSize)
    )
    try await withHostedTestWindow(host, size: CGSize(width: 320, height: 844)) { window in
      let horizontal = try await Self.waitForPhotoRow(in: window)
      #expect(
        horizontal.contentSize.width > horizontal.bounds.width + 1,
        "Attachments need a horizontal scroll region"
      )
      let vertical = try #require(
        Self.descendants(of: window)
          .compactMap { $0 as? UIScrollView }
          .first { $0.contentSize.height > $0.bounds.height + 1 && $0 !== horizontal }
      )
      let initialVerticalOffset = vertical.contentOffset
      #expect(horizontal.contentSize.height <= horizontal.bounds.height + 1)

      horizontal.setContentOffset(
        CGPoint(x: horizontal.contentSize.width - horizontal.bounds.width, y: 0),
        animated: false
      )
      host.view.layoutIfNeeded()
      #expect(vertical.contentOffset == initialVerticalOffset)

      horizontal.setContentOffset(.zero, animated: false)
      host.view.layoutIfNeeded()
      #expect(vertical.contentOffset == initialVerticalOffset)

      vertical.setContentOffset(CGPoint(x: 0, y: 200), animated: false)
      host.view.layoutIfNeeded()
      #expect(vertical.contentOffset.y == 200)
      #expect(horizontal.contentOffset.x == 0)
    }
  }

  private static func waitForPhotoRow(in window: UIWindow) async throws -> UIScrollView {
    try await Wait.until { @MainActor in
      Self.photoRow(in: window) != nil
    } _: {
      "Feedback photos did not render"
    }
    return try #require(photoRow(in: window))
  }

  private static func photoRow(in window: UIWindow) -> UIScrollView? {
    window.layoutIfNeeded()
    return descendants(of: window)
      .compactMap { $0 as? UIScrollView }
      .first { abs($0.contentSize.height - 200) < 1 && $0.contentSize.width > 0 }
  }

  private static func photoData(_ size: CGSize) throws -> Data {
    try #require(
      UIGraphicsImageRenderer(size: size)
        .image { context in
          UIColor.systemBlue.setFill()
          context.fill(CGRect(origin: .zero, size: size))
        }
        .pngData()
    )
  }

  private static func descendants(of view: UIView) -> [UIView] {
    [view] + view.subviews.flatMap { descendants(of: $0) }
  }
}
