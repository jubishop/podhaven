// Copyright Justin Bishop, 2025

import SwiftSyntaxMacrosTestSupport
import Testing

@testable import GRDBSavedMacroPlugin
@testable import GRDBSavedMacro

struct GRDBSavedMacroTests {
  @Test("GRDBSaved macro expansion for struct with unsaved type")
  func testGRDBSavedMacroExpansion() throws {
    // Test input code
    let inputSource = """
    import Tagged

    @GRDBSaved<UnsavedTest>
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
      macros: ["GRDBSaved": GRDBSavedMacro.self],
      indentationWidth: .spaces(2)
    ) == (), "Macro expansion should succeed without errors")
  }
}
