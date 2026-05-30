// Copyright Justin Bishop, 2025

import SwiftSyntaxMacrosTestSupport
import XCTest

@testable import SavedMacroPlugin

final class SavedMacroTests: XCTestCase {
  func testSavedMacroExpansion() {
    assertMacroExpansion(
      """
      import Tagged

      @Saved<UnsavedTest>
      struct Test {}

      struct UnsavedTest {}
      """,
      expandedSource: """
        import Tagged
        struct Test {

          typealias ID = Tagged<Self, Int64>

          let id: ID

          let creationDate: Date

          var unsaved: UnsavedTest



          init(id: ID, creationDate: Date, from unsaved: UnsavedTest) {
            self.id = id
            self.creationDate = creationDate
            self.unsaved = unsaved
          }
        }

        struct UnsavedTest {}
        """,
      macros: ["Saved": SavedMacro.self],
      indentationWidth: .spaces(2)
    )
  }
}
