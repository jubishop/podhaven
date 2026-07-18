// Copyright Justin Bishop, 2026

import SwiftUI
import Testing
import UIKit

@testable import PodHaven

@Suite("of toolbar icon color tests", .container)
@MainActor struct ToolbarIconColorTests {
  private struct MenuFixture: View {
    var body: some View {
      NavigationStack {
        Color.black
          .toolbar {
            ToolbarItem(placement: .primaryAction) {
              Menu {
                Button("Action") {}
              } label: {
                AppIcon.pauseButton.image
              }
              .accessibilityLabel("Episode Actions")
            }
          }
          .toolbarRole(.editor)
      }
      .preferredColorScheme(.dark)
    }
  }

  @Test("toolbar menus retain their icon color and accessibility label")
  func toolbarMenusRetainTheirIconColorAndAccessibilityLabel() throws {
    let host = UIHostingController(rootView: MenuFixture())
    let scene = try #require(
      UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    )
    let window = UIWindow(windowScene: scene)
    window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
    window.rootViewController = host
    window.makeKeyAndVisible()
    host.view.layoutIfNeeded()
    defer { window.isHidden = true }

    let descendants = Self.descendants(of: window)
    let toolbarControl: UIView
    if ProcessInfo.processInfo.isiOSAppOnMac {
      toolbarControl = try #require(
        descendants.first { $0.accessibilityLabel == "Episode Actions" }
      )
    } else {
      let navigationBar = try #require(descendants.first { $0 is UINavigationBar })
      toolbarControl = try #require(
        Self.descendants(of: navigationBar)
          .first {
            $0 is UIControl && !$0.bounds.isEmpty
          }
      )
    }

    let expectedColor = UIColor(AppIcon.pauseButton.color(for: .dark))
    let toolbarFrame = toolbarControl.convert(toolbarControl.bounds, to: window)
    #expect(Self.contains(expectedColor, in: toolbarFrame, rendering: window))
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
      color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
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
