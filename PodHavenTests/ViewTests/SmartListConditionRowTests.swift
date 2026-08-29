// Copyright Justin Bishop, 2026

import SwiftUI
import Testing
import UIKit

@testable import PodHaven

@Suite("of smart list condition row tests", .container)
@MainActor struct SmartListConditionRowTests {
  private struct Fixture: View {
    @State private var episodeCondition: EditableCondition = {
      var condition = EditableCondition()
      condition.kind = .episodeTitleOrDescription
      return condition
    }()

    @State private var podcastCondition: EditableCondition = {
      var condition = EditableCondition()
      condition.kind = .podcastTitleOrDescription
      return condition
    }()

    var body: some View {
      Form {
        SmartListConditionRow(condition: $episodeCondition) {}
        SmartListConditionRow(condition: $podcastCondition) {}
      }
    }
  }

  @Test(
    "combined-text pickers expose their full meaning to assistive technology",
    .enabled(
      if: ProcessInfo.processInfo.isiOSAppOnMac,
      "SwiftUI does not expose hosted accessibility elements in iOS Simulator"
    )
  )
  func combinedTextPickersExposeFullAccessibilityValues() async throws {
    let window = try Self.makeWindow(Fixture())
    defer { window.isHidden = true }

    try await Wait.until(
      maxAttempts: 100,
      { @MainActor in
        window.rootViewController?.view.setNeedsLayout()
        window.rootViewController?.view.layoutIfNeeded()
        let labels = Set(
          Self.accessibilityElements(in: window).compactMap(\.accessibilityLabel)
        )
        return labels.contains("Condition, Episode Title or Description")
          && labels.contains("Condition, Podcast Title or Description")
      },
      { @MainActor in
        let semantics = Self.accessibilityElements(in: window)
          .filter { $0.accessibilityLabel != nil }
          .map { "\($0.accessibilityLabel ?? "nil"): \($0.accessibilityValue ?? "nil")" }
        return "Combined-text picker semantics were \(semantics)"
      }
    )
  }

  private static func makeWindow<V: View>(_ rootView: V) throws -> UIWindow {
    let host = UIHostingController(rootView: rootView)
    let scene = try #require(
      UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    )
    let window = UIWindow(windowScene: scene)
    window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
    window.rootViewController = host
    window.makeKeyAndVisible()
    host.view.layoutIfNeeded()
    return window
  }

  private static func accessibilityElements(in root: NSObject) -> [NSObject] {
    var visited: Set<ObjectIdentifier> = []

    func collect(from object: NSObject) -> [NSObject] {
      guard visited.insert(ObjectIdentifier(object)).inserted else { return [] }

      var result = object.isAccessibilityElement ? [object] : []
      if let view = object as? UIView {
        result.append(contentsOf: view.subviews.flatMap { collect(from: $0) })
      }

      let count = object.accessibilityElementCount()
      if count != NSNotFound, count > 0 {
        for index in 0..<count {
          if let child = object.accessibilityElement(at: index) as? NSObject {
            result.append(contentsOf: collect(from: child))
          }
        }
      }

      return result
    }

    return collect(from: root)
  }
}
