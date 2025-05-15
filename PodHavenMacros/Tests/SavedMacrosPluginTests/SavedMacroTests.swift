// Copyright Justin Bishop, 2025

import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
import SavedMacrosPlugin

final class SavedMacroTests: XCTestCase {
  // Test that the macro works by applying it to a test struct
  func testSavedMacro() {
    // We'll just test that the macro completes without failure
    // Using a minimal assertMacroExpansion call
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

  var id: ID

  var unsaved: UnsavedTest

  init(id: ID, from unsaved: UnsavedTest) {
    self.id = id
    self.unsaved = unsaved
  }
}

struct UnsavedTest {}
""",
      macros: ["Saved": SavedMacro.self],
      indentationWidth: .spaces(2)
    )
    
    // Since we can't directly get the expanded source to inspect it,
    // we're just checking that the macro expands without throwing errors
    XCTAssert(true, "Macro expansion succeeded")
  }
}
