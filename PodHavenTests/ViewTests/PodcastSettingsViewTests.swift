// Copyright Justin Bishop, 2026

import FactoryKit
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

  @Test("unsubscribed podcasts note that automation applies only while subscribed")
  func unsubscribedPodcastsNoteAutomationNeedsSubscription() async throws {
    Container.shared.transcriptionAvailability().$state.new(.available)

    let subscribed = try await Self.hostSettings(subscriptionDate: Date())
    let unsubscribed = try await Self.hostSettings(subscriptionDate: nil)

    let addedRows = zip(unsubscribed.rows, subscribed.rows).map { $0 - $1 }
    #expect(unsubscribed.rows.count == subscribed.rows.count)
    // Playback, Queue, Storage, Transcription, Recommendations, Notifications.
    #expect(addedRows == [0, 1, 1, 1, 0, 1])
    #expect(unsubscribed.controlsEnabled == subscribed.controlsEnabled)
    #expect(unsubscribed.controlsEnabled.allSatisfy { $0 })
  }

  private static func hostSettings(
    subscriptionDate: Date?
  ) async throws -> (rows: [Int], controlsEnabled: [Bool]) {
    let podcast = try await Create.podcast(
      subscriptionDate: subscriptionDate,
      queueAllEpisodes: .onBottom,
      autoQueueLimit: PodcastSettings.defaultAutoQueueLimit
    )
    let displayed = DisplayedPodcast(podcast)
    let viewModel = PodcastDetailViewModel(podcast: displayed)
    let host = TestHostingController(
      rootView: PodcastSettingsView(viewModel: viewModel, settings: displayed.settings)
    )
    return try await withHostedTestWindow(host, size: CGSize(width: 390, height: 2400)) { _ in
      host.view.setNeedsLayout()
      host.view.layoutIfNeeded()
      let descendants = Self.descendants(of: host.view)
      let form = try #require(descendants.compactMap { $0 as? UICollectionView }.first)
      let rows = (0..<form.numberOfSections).map { form.numberOfItems(inSection: $0) }
      let controls = descendants.compactMap { $0 as? UIControl }
        .filter { $0 is UISwitch || $0 is UISegmentedControl || $0 is UISlider }
      try #require(!controls.isEmpty)
      return (rows, controls.map(\.isEnabled))
    }
  }

  private static func descendants(of view: UIView) -> [UIView] {
    [view] + view.subviews.flatMap(descendants)
  }
}
