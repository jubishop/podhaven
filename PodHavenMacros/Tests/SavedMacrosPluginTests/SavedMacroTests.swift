// Copyright Justin Bishop, 2025

import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
import SavedMacrosPlugin

final class SavedMacroTests: XCTestCase {
  func testMacro() {
    assertMacroExpansion(
      """
      @Saved<UnsavedTest>
      struct Test {
      }
      """,
      expandedSource: """
      struct Test {
        // MARK: - Saved
      
        typealias ID = Tagged<Self, Int64>
        var id: ID
        var unsaved: UnsavedTest
      
        init(id: ID, from unsaved: UnsavedTest) {
          self.id = id
          self.unsaved = unsaved
        }
      }
      """,
      macros: ["Saved": SavedMacro.self]
    )
  }
}
