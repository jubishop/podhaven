// Copyright Justin Bishop, 2025

import SavedMacrosPlugin
import SwiftSyntaxMacrosTestSupport
import Testing

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
    let expectedExpansion = """
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
    
    // Perform the test using modern Swift testing syntax
    #expect(assertMacroExpansion(
      inputSource,
      expandedSource: expectedExpansion,
      macros: ["Saved": SavedMacro.self],
      indentationWidth: .spaces(2)
    ) == (), "Macro expansion should succeed without errors")
  }
}
