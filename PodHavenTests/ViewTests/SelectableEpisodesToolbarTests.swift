// Copyright Justin Bishop, 2026

import Foundation
import SwiftUI
import Testing
import UIKit

@testable import PodHaven

@Suite("of selectable episode toolbar tests", .container)
@MainActor struct SelectableEpisodesToolbarTests {
  private struct Fixture: View {
    let viewModel: EpisodesListViewModel

    var body: some View {
      ScrollView {
        VStack {
          SelectedEpisodesActionsMenuContent(viewModel: viewModel)
        }
      }
    }
  }

  @Test(
    "multi-select actions omit the misleading play command",
    .enabled(
      if: ProcessInfo.processInfo.isiOSAppOnMac,
      "SwiftUI does not expose hosted accessibility elements in iOS Simulator"
    )
  )
  func multiSelectActionsOmitPlayCommand() async throws {
    let setup = try await EpisodesListTestHelpers.setupFourTaggedEpisodes()
    let viewModel = try await EpisodesListTestHelpers.makeViewModel(title: "Toolbar Actions")
    try await EpisodesListTestHelpers.loadEntries(into: viewModel, episodes: setup.episodes)
    viewModel.setSelecting(true)
    EpisodesListTestHelpers.select(viewModel, ids: [setup.ep1.id])

    try await Self.withWindow(Fixture(viewModel: viewModel)) { window in

      try await Wait.until(
        { @MainActor in
          window.rootViewController?.view.setNeedsLayout()
          window.rootViewController?.view.layoutIfNeeded()
          return Self.accessibilityLabels(in: window).contains("Queue")
        },
        { @MainActor in
          """
          The selected-episode actions did not enter the accessibility tree; labels were \
          \(Self.accessibilityLabels(in: window).sorted())
          """
        }
      )

      #expect(!Self.accessibilityLabels(in: window).contains("Play Selected Episodes"))
    }
  }

  private static func withWindow<V: View>(
    _ rootView: V,
    _ body: @MainActor (UIWindow) async throws -> Void
  ) async throws {
    try await withHostedTestWindow(TestHostingController(rootView: rootView), body)
  }

  private static func accessibilityLabels(in root: NSObject) -> Set<String> {
    Set(accessibilityElements(in: root).compactMap(\.accessibilityLabel))
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
