// Copyright Justin Bishop, 2024

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of HTML Regex tests")
actor HTMLRegexTests {
  @Test("that HTML regexes work")
  func testHTMLRegexes() throws {
    #expect("Words with <br/> making new lines".isHTML() == true)
    #expect("Words with <br /> spaced properly".isHTML() == true)
    #expect("Gotta love <p> for paragraphs</p>".isHTML() == true)
    #expect("Normal text discussing 1 < 2 and 4 > 3".isHTML() == false)
    #expect("If you open a tag <p> but don't close it".isHTML() == false)
    #expect("Hello, world. New stuff! And, commas; too".isHTML() == false)
  }
}
