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
      let screenshot = UIGraphicsImageRenderer(bounds: window.bounds)
        .image { _ in
          window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
      Attachment.record(
        try #require(screenshot.pngData()),
        named: "feedback-photos-\(count)-\(dynamicTypeSize).png"
      )
      let elements = Self.accessibilityElements(in: window)
      let attachments = elements.filter {
        $0.accessibilityLabel?.hasPrefix("Attached photo ") == true
      }
      try #require(attachments.count == count)
      let firstFrame = try #require(attachments.first).accessibilityFrame
      for (index, attachment) in attachments.enumerated() {
        #expect(attachment.accessibilityLabel == "Attached photo \(index + 1)")
        #expect(attachment.accessibilityValue == "\(index + 1) of \(count)")
        #expect(attachment.accessibilityTraits.contains(.image))
        let frame = attachment.accessibilityFrame
        #expect(abs(frame.midY - firstFrame.midY) < 1)
        #expect(abs(frame.height - 200) < 1)
        #expect(abs(frame.width / frame.height - sizes[index].width / sizes[index].height) < 0.01)
        if index > 0 {
          #expect(frame.minX > attachments[index - 1].accessibilityFrame.maxX)
        }
      }
    }
  }

  @Test(
    "overflowing photos scroll in both directions without moving the form",
    .enabled(if: ProcessInfo.processInfo.isiOSAppOnMac),
    arguments: [DynamicTypeSize.large, .accessibility5]
  )
  func scrollingAndAccessibility(dynamicTypeSize: DynamicTypeSize) async throws {
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
      let scrollViews = Self.descendants(of: window).compactMap { $0 as? UIScrollView }
      let horizontal = try #require(
        scrollViews.first { $0.contentSize.width > $0.bounds.width + 1 },
        "Attachments need a horizontal scroll region"
      )
      let vertical = try #require(
        scrollViews.first { $0.contentSize.height > $0.bounds.height + 1 && $0 !== horizontal }
      )
      let initialVerticalOffset = vertical.contentOffset
      #expect(horizontal.contentSize.height <= horizontal.bounds.height + 1)

      let initialPhotos = Self.accessibilityElements(in: window)
        .filter { $0.accessibilityLabel?.hasPrefix("Attached photo ") == true }
      let last = try #require(initialPhotos.last)
      #expect(last.accessibilityLabel == "Attached photo 5")
      let visibleFrame = horizontal.convert(horizontal.bounds, to: window.screen.coordinateSpace)
      #expect(last.accessibilityFrame.minX >= visibleFrame.maxX)

      horizontal.setContentOffset(
        CGPoint(x: horizontal.contentSize.width - horizontal.bounds.width, y: 0),
        animated: false
      )
      host.view.layoutIfNeeded()
      let revealedLast = try #require(
        Self.accessibilityElements(in: window).first { $0.accessibilityLabel == "Attached photo 5" }
      )
      #expect(visibleFrame.contains(revealedLast.accessibilityFrame))
      #expect(revealedLast.accessibilityValue == "5 of 5")
      #expect(vertical.contentOffset == initialVerticalOffset)

      horizontal.setContentOffset(.zero, animated: false)
      host.view.layoutIfNeeded()
      let revealedFirst = try #require(
        Self.accessibilityElements(in: window).first { $0.accessibilityLabel == "Attached photo 1" }
      )
      #expect(visibleFrame.contains(revealedFirst.accessibilityFrame))
      #expect(vertical.contentOffset == initialVerticalOffset)

      vertical.setContentOffset(CGPoint(x: 0, y: 200), animated: false)
      host.view.layoutIfNeeded()
      #expect(vertical.contentOffset.y == 200)
      #expect(horizontal.contentOffset.x == 0)
    }
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

  private static func accessibilityElements(in root: NSObject)
    -> [NSObject]
  {
    var visited: Set<ObjectIdentifier> = []
    func collect(_ object: NSObject) -> [NSObject] {
      guard visited.insert(ObjectIdentifier(object)).inserted else { return [] }
      var result = object.isAccessibilityElement ? [object] : []
      if let view = object as? UIView {
        result += view.subviews.flatMap { collect($0) }
      }
      let count = object.accessibilityElementCount()
      if count != NSNotFound, count > 0 {
        for index in 0..<count {
          if let child = object.accessibilityElement(at: index) as? NSObject {
            result += collect(child)
          }
        }
      }
      return result
    }
    return collect(root)
  }
}
