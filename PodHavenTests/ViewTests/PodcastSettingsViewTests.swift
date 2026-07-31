// Copyright Justin Bishop, 2026

import SwiftUI
import Testing
import UIKit

@testable import PodHaven

private let supportsHostedPodcastSettingsInspection = ProcessInfo.processInfo.isiOSAppOnMac

@Suite("of PodcastSettingsView tests", .container)
@MainActor struct PodcastSettingsViewTests {
  private struct ToggleLabelMarker: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
      let view = UIView()
      view.accessibilityIdentifier = "stacked-toggle-label-marker"
      return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
  }

  private struct AutomaticTranscriptionToggleFixture: View {
    @State private var isOn = true

    var body: some View {
      SettingsRow(infoText: "Automatic transcription details") {
        Toggle("Always Transcribe New Episodes", isOn: $isOn)
          .toggleStyle(.stacked)
      }
      .padding()
    }
  }

  private struct StackedToggleSpacingFixture: View {
    @State private var isOn = true

    var body: some View {
      Toggle(isOn: $isOn) {
        ToggleLabelMarker()
          .frame(width: 80, height: 20)
      }
      .toggleStyle(.stacked)
      .padding()
    }
  }

  @Test("stacked toggles use the settings control spacing")
  func stackedTogglesUseTheSettingsControlSpacing() async throws {
    let host = UIHostingController(rootView: StackedToggleSpacingFixture())
    let scene = try #require(
      UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    )
    let window = UIWindow(windowScene: scene)
    window.frame = CGRect(x: 0, y: 0, width: 200, height: 120)
    window.rootViewController = host
    window.makeKeyAndVisible()
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async {
        continuation.resume()
      }
    }
    defer { window.isHidden = true }

    host.view.setNeedsLayout()
    host.view.layoutIfNeeded()
    let descendants = Self.descendants(of: host.view)
    let switchControl = try #require(descendants.compactMap { $0 as? UISwitch }.first)
    let switchFrame = switchControl.convert(switchControl.bounds, to: window)
    let labelFrame = try #require(
      descendants
        .filter {
          $0.accessibilityIdentifier == "stacked-toggle-label-marker" && !$0.bounds.isEmpty
        }
        .map { $0.convert($0.bounds, to: window) }
        .filter { $0.maxY <= switchFrame.minY }
        .max { $0.maxY < $1.maxY }
    )
    let spacing = switchFrame.minY - labelFrame.maxY

    #expect(
      abs(spacing - 24) <= 1,
      "Stacked toggles should use 24-point spacing; found \(spacing)"
    )
  }

  @Test(
    "automatic transcription toggle is below its label",
    .enabled(
      if: supportsHostedPodcastSettingsInspection,
      "SwiftUI does not expose hosted accessibility elements in iOS Simulator"
    )
  )
  func automaticTranscriptionToggleIsBelowItsLabel() async throws {
    let host = UIHostingController(
      rootView: AutomaticTranscriptionToggleFixture()
        .transaction { transaction in
          transaction.disablesAnimations = true
        }
    )
    let scene = try #require(
      UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    )
    let window = UIWindow(windowScene: scene)
    window.frame = CGRect(x: 0, y: 0, width: 390, height: 160)
    window.rootViewController = host
    window.makeKeyAndVisible()
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async {
        continuation.resume()
      }
    }
    defer { window.isHidden = true }

    try await Wait.until(
      { @MainActor in
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        return Self.accessibilityElements(in: window)
          .contains { $0.accessibilityLabel?.contains("Always Transcribe New Episodes") == true }
      },
      { @MainActor in "Automatic transcription toggle did not enter the accessibility tree" }
    )

    let elements = Self.accessibilityElements(in: window)
    let toggles = elements.filter {
      $0.accessibilityLabel?.contains("Always Transcribe New Episodes") == true
    }
    #expect(toggles.count == 1)
    let switchControl = try #require(
      Self.descendants(of: host.view).compactMap { $0 as? UISwitch }.first
    )
    let switchFrame = switchControl.convert(
      switchControl.bounds,
      to: window
    )
    let infoFrame = try #require(
      elements.first { $0.accessibilityLabel == "More Info" }
    )
    let convertedInfoFrame = window.convert(
      infoFrame.accessibilityFrame,
      from: window.screen.coordinateSpace
    )

    #expect(
      switchFrame.minY > convertedInfoFrame.maxY,
      """
      The automatic transcription switch should sit below the label row; found switch frame \
      \(switchFrame) beside info frame \(convertedInfoFrame)
      """
    )
  }

  private static func descendants(of view: UIView) -> [UIView] {
    [view] + view.subviews.flatMap(descendants)
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
