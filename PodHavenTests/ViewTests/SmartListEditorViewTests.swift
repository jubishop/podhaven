// Copyright Justin Bishop, 2026

import SwiftUI
import Testing
import UIKit

@testable import PodHaven

@Suite("of SmartListEditorView tests", .container)
@MainActor final class SmartListEditorViewTests {
  @Test("removing a group while its section is rendered does not trap")
  func removeGroupWhileRendered() throws {
    let viewModel = SmartListEditorViewModel(
      mode: .create,
      filter: SmartListFilter(groups: [SmartListFilter.Group(combinator: .any)])
    )
    let host = UIHostingController(rootView: SmartListEditorView(viewModel: viewModel))
    let scene = try #require(
      UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    )
    let window = UIWindow(windowScene: scene)
    window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
    window.rootViewController = host
    window.makeKeyAndVisible()
    host.view.layoutIfNeeded()

    let group = try #require(viewModel.groups.first)
    viewModel.removeGroup(group.id)
    host.view.setNeedsLayout()
    host.view.layoutIfNeeded()

    #expect(viewModel.groups.isEmpty)
  }
}
