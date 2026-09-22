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

  @Test(
    "freshness selection aligns with its label and help button",
    .enabled(if: supportsHostedPodcastSettingsInspection),
    arguments: [FreshnessCadence?.none, .daily, .twiceWeekly, .evergreen]
  )
  func freshnessSelectionAlignment(cadence: FreshnessCadence?) async throws {
    let podcast = try await Create.podcast(title: "Freshness layout", freshnessCadence: cadence)
    let displayed = DisplayedPodcast(podcast)
    let host = TestHostingController(
      rootView: PodcastSettingsView(
        viewModel: PodcastDetailViewModel(podcast: displayed),
        settings: displayed.settings
      )
      .transaction { $0.disablesAnimations = true }
    )
    try await withHostedTestWindow(host, size: CGSize(width: 320, height: 844)) { window in
      let scroll = try #require(
        Self.descendants(of: host.view).compactMap { $0 as? UIScrollView }.first
      )
      scroll.setContentOffset(
        CGPoint(
          x: 0,
          y: max(
            0,
            scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom
          )
        ),
        animated: false
      )
      host.view.layoutIfNeeded()
      let selection = cadence?.displayName ?? "Auto"
      try await Wait.until { @MainActor in
        Self.accessibilityElements(in: window).contains { $0.accessibilityLabel == "Freshness" }
      } _: {
        "Freshness setting did not appear"
      }
      let elements = Self.accessibilityElements(in: window)
      let label = try #require(
        elements.first {
          $0.accessibilityLabel == "Freshness" && !$0.accessibilityTraits.contains(.button)
        }
      )
      let picker = try #require(
        elements.first {
          $0.accessibilityTraits.contains(.button)
            && ($0.accessibilityLabel?.contains(selection) == true
              || $0.accessibilityValue == selection)
        },
        "Missing selection \(selection): \(elements.map { "\($0.accessibilityLabel ?? "nil"): \($0.accessibilityValue ?? "nil")" })"
      )
      let labelFrame = label.accessibilityFrame
      let pickerFrame = picker.accessibilityFrame
      #expect(picker.accessibilityLabel?.contains("Freshness") == true)
      let info = try #require(
        elements.filter { $0.accessibilityLabel == "More Info" }
          .min {
            abs($0.accessibilityFrame.midY - labelFrame.midY)
              < abs($1.accessibilityFrame.midY - labelFrame.midY)
          }
      )
      #expect(
        abs(labelFrame.midY - pickerFrame.midY) <= 2,
        "Freshness label \(labelFrame) and selection \(pickerFrame) should align"
      )
      #expect(
        abs(info.accessibilityFrame.midY - pickerFrame.midY) <= 2,
        "Freshness help \(info.accessibilityFrame) and selection \(pickerFrame) should align"
      )
      #expect(labelFrame.maxX <= pickerFrame.minX)
      #expect(pickerFrame.maxX <= info.accessibilityFrame.minX)
      #expect(
        elements.contains { $0.accessibilityLabel?.hasPrefix("Resolved to ") == true }
          == (cadence == nil)
      )
      let image = UIGraphicsImageRenderer(bounds: window.bounds)
        .image { _ in
          window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
      Attachment.record(
        try #require(image.pngData()),
        named: "freshness-\(selection).png"
      )
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
  }

  @Test(
    "automatic transcription toggle is below its label",
    .enabled(
      if: supportsHostedPodcastSettingsInspection,
      "SwiftUI does not expose hosted accessibility elements in iOS Simulator"
    )
  )
  func automaticTranscriptionToggleIsBelowItsLabel() async throws {
    let host = TestHostingController(
      rootView: AutomaticTranscriptionToggleFixture()
        .transaction { transaction in
          transaction.disablesAnimations = true
        }
    )
    try await withHostedTestWindow(host, size: CGSize(width: 390, height: 160)) { window in

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
  }

  @Test(
    "silence help popovers expose their complete text on narrow layouts",
    .enabled(if: supportsHostedPodcastSettingsInspection)
  )
  func silenceHelpPopovers() async throws {
    for size in [DynamicTypeSize.large, .accessibility3] {
      for (index, help) in [SilenceSettingsHelp.text, QuietAudioProtectionHelp.text].enumerated() {
        let host = TestHostingController(
          rootView:
            VStack {
              SettingsRow(infoText: help) { Text("Playback setting") }
              Spacer()
            }
            .padding()
            .environment(\.dynamicTypeSize, size)
        )
        host.traitOverrides.preferredContentSizeCategory =
          size == .large ? .large : .accessibilityExtraExtraLarge
        try await withHostedTestWindow(host, size: CGSize(width: 320, height: 844)) { window in
          try await Wait.until { @MainActor in
            Self.accessibilityElements(in: window).contains { $0.accessibilityLabel == "More Info" }
          } _: {
            "Help button did not appear"
          }
          let info = try #require(
            Self.accessibilityElements(in: window).first { $0.accessibilityLabel == "More Info" }
          )
          #expect(info.accessibilityActivate())
          try await Wait.until { @MainActor in
            Self.accessibilityElements(in: window).contains { $0.accessibilityLabel == help }
          } _: {
            "Complete help text did not appear"
          }
          let text = try #require(
            Self.accessibilityElements(in: window).first { $0.accessibilityLabel == help }
          )
          let frame = window.convert(text.accessibilityFrame, from: window.screen.coordinateSpace)
          #expect(frame.width > 0)
          #expect(frame.minX >= 0 && frame.maxX <= 320)
          #expect(frame.minY >= 0 && frame.maxY <= 844)
          let popover = try #require(host.presentedViewController?.view)
          let image = UIGraphicsImageRenderer(bounds: popover.bounds)
            .image { _ in
              popover.drawHierarchy(in: popover.bounds, afterScreenUpdates: true)
            }
          Attachment.record(
            try #require(image.pngData()),
            named: "silence-help-\(index)-\(size).png"
          )
        }
      }
    }
  }

  @Test(
    "oversized silence help remains scrollable to its final paragraph",
    .enabled(if: supportsHostedPodcastSettingsInspection)
  )
  func overflowingSilenceHelp() async throws {
    let help = String(repeating: SilenceSettingsHelp.text + "\n\n", count: 4)
    let host = TestHostingController(
      rootView:
        VStack {
          SettingsRow(infoText: help) { Text("Playback setting") }
          Spacer()
        }
        .padding()
    )
    try await withHostedTestWindow(host, size: CGSize(width: 320, height: 480)) { window in
      try await Wait.until { @MainActor in
        Self.accessibilityElements(in: window).contains { $0.accessibilityLabel == "More Info" }
      } _: {
        "Help button did not appear"
      }
      try activateHostedControl(
        try #require(
          Self.accessibilityElements(in: window).first { $0.accessibilityLabel == "More Info" }
        )
      )
      try await Wait.until { @MainActor in
        host.presentedViewController != nil
      } _: {
        "Popover did not open"
      }
      let popover = try #require(host.presentedViewController?.view)
      popover.layoutIfNeeded()
      let scroll = try #require(
        Self.descendants(of: popover).compactMap { $0 as? UIScrollView }
          .first {
            $0.isScrollEnabled && $0.contentSize.height > $0.bounds.height
          },
        "Help that exceeds the available height needs a scrollable presentation"
      )
      scroll.setContentOffset(
        CGPoint(x: 0, y: scroll.contentSize.height - scroll.bounds.height),
        animated: false
      )
      #expect(scroll.contentOffset.y > 0)
      let image = UIGraphicsImageRenderer(bounds: popover.bounds)
        .image { _ in
          popover.drawHierarchy(in: popover.bounds, afterScreenUpdates: true)
        }
      Attachment.record(try #require(image.pngData()), named: "silence-help-scrolled.png")
    }
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
