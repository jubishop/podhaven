// Copyright Justin Bishop, 2026

import SwiftUI
import Testing
import UIKit

@testable import PodHaven

@Suite("of SmartListEditorView tests", .container)
@MainActor final class SmartListEditorViewTests {
  @Test("removing a group while its section is rendered does not trap")
  func removeGroupWhileRendered() async throws {
    let viewModel = SmartListEditorViewModel(
      mode: .create,
      filter: SmartListFilter(groups: [SmartListFilter.Group(combinator: .any)])
    )
    let host = TestHostingController(rootView: SmartListEditorView(viewModel: viewModel))
    try await withHostedTestWindow(host, size: CGSize(width: 390, height: 844)) { window in
      host.view.layoutIfNeeded()

      let group = try #require(viewModel.groups.first)
      viewModel.removeGroup(group.id)
      host.view.setNeedsLayout()
      host.view.layoutIfNeeded()

      #expect(viewModel.groups.isEmpty)
    }
  }
}
