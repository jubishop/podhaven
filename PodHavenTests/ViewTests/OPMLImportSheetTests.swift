// Copyright Justin Bishop, 2026

import FactoryKit
import SwiftUI
import Testing
import UIKit

@testable import PodHaven

@Suite("of OPMLImportSheet tests", .container)
@MainActor struct OPMLImportSheetTests {
  @DynamicInjected(\.opmlViewModel) private var opmlViewModel

  @Test("large imports render a bounded number of rows in each section")
  func largeImportsRenderBoundedRows() async throws {
    let limit = OPMLImportSheetSection.maxVisibleRows
    let opmlFile = OPMLFile(title: "Large Import", skippedCount: 0)
    opmlFile.waiting = .init(
      (0..<limit * 3).map { OPMLOutline(status: .waiting, text: "Waiting \($0)") }
    )
    opmlFile.finished = .init(
      (0..<limit * 2).map { OPMLOutline(status: .finished, text: "Finished \($0)") }
    )
    opmlFile.failed = .init(
      (0..<limit / 2).map { OPMLOutline(status: .failed, text: "Failed \($0)") }
    )

    let host = TestHostingController(
      rootView: VStack { OPMLImportSheet(viewModel: opmlViewModel, opmlFile: opmlFile) }
    )
    try await withHostedTestWindow(host) { _ in
      let list = try #require(
        Self.descendants(of: host.view).compactMap { $0 as? UICollectionView }.first
      )
      let rows = (0..<list.numberOfSections).map { list.numberOfItems(inSection: $0) }
      #expect(rows == [limit, limit / 2, limit])
    }
  }

  private static func descendants(of view: UIView) -> [UIView] {
    [view] + view.subviews.flatMap(descendants)
  }
}
