// Copyright Justin Bishop, 2026

import SwiftUI
import Testing
import UIKit

@testable import PodHaven

@Suite("of SmartListEditorView tests", .container)
@MainActor final class SmartListEditorViewTests {
  @Test("removing the nested group while its section is rendered does not trap")
  func removeNestedGroupWhileRendered() {
    let viewModel = SmartListEditorViewModel(
      mode: .create,
      filter: SmartListFilter(nested: SmartListFilter.Group(combinator: .any))
    )
    let host = UIHostingController(rootView: SmartListEditorView(viewModel: viewModel))
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = host
    window.makeKeyAndVisible()
    host.view.layoutIfNeeded()

    viewModel.removeNestedGroup()
    host.view.setNeedsLayout()
    host.view.layoutIfNeeded()

    #expect(viewModel.nested == nil)
  }
}
