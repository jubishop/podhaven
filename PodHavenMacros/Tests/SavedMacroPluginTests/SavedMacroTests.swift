// Copyright Justin Bishop, 2025

import SwiftSyntaxMacrosTestSupport
import Testing

@testable import SavedMacro
@testable import SavedMacroPlugin

struct SavedMacroTests {
  @Test("Saved macro expansion for struct with unsaved type")
  func testSavedMacroExpansion() throws {
    // Test input code
    let inputSource = """
      import Tagged

      @Saved<UnsavedTest>
      struct Test {}

      struct UnsavedTest {}
      """

    // Expected expanded code
    let expected = """
      import Tagged
      struct Test {

        typealias ID = Tagged<Self, Int64>

        var id: ID

        var unsaved: UnsavedTest

        init(id: ID, from unsaved: UnsavedTest) {
          self.id = id
          self.unsaved = unsaved
        }
      }

      struct UnsavedTest {}
      """

    assertMacroExpansion(
      inputSource,
      expandedSource: expected,
      macros: ["Saved": SavedMacro.self],
      indentationWidth: .spaces(2)
    )
  }
}
