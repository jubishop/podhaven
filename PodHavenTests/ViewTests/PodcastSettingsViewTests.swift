// Copyright Justin Bishop, 2026

import SwiftUI
import Testing
import UIKit

@testable import PodHaven

@Suite("of PodcastSettingsView tests", .container)
@MainActor struct PodcastSettingsViewTests {
  private final class ToggleLabelMarkerView: UIView {}

  private struct ToggleLabelMarker: UIViewRepresentable {
    func makeUIView(context: Context) -> ToggleLabelMarkerView {
      ToggleLabelMarkerView()
    }

    func updateUIView(_ uiView: ToggleLabelMarkerView, context: Context) {}
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
    let host = TestHostingController(rootView: StackedToggleSpacingFixture())
    try await withHostedTestWindow(host, size: CGSize(width: 200, height: 120)) { window in

      host.view.setNeedsLayout()
      host.view.layoutIfNeeded()
      let descendants = Self.descendants(of: host.view)
      let switchControl = try #require(descendants.compactMap { $0 as? UISwitch }.first)
      let switchFrame = switchControl.convert(switchControl.bounds, to: window)
      let labelFrame = try #require(
        descendants
          .filter {
            $0 is ToggleLabelMarkerView && !$0.bounds.isEmpty
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
  }

  private static func descendants(of view: UIView) -> [UIView] {
    [view] + view.subviews.flatMap(descendants)
  }
}
