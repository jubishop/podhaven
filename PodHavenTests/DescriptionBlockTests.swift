// Copyright Justin Bishop, 2026

import SwiftUI
import Testing

@testable import PodHaven

@Suite("of description blocks")
struct DescriptionBlockTests {
  @Test("long HTML keeps every character and attribute in bounded ordered blocks")
  func longHTMLIsLossless() async throws {
    let html = String(
      repeating: """
        <p><b>Bold</b> and <i>italic</i> <u>underlined</u> <s>deleted</s> <mark>marked</mark> \
        👩🏽‍💻 é 🇯🇵 &amp; <a href="https://example.com/notes">notes</a> at 12:34.</p>
        <ol><li>First item</li><li>Second item</li></ol>
        """,
      count: 1484
    )
    let original = try #require(
      await HTMLContent.descriptionAttributedString(html: html, font: .body, linkTimestamps: true)
    )
    let blocks = await HTMLContent.descriptionBlocks(html: html, font: .body, linkTimestamps: true)
    #expect(blocks.count > 100)
    #expect(
      blocks.allSatisfy { !$0.content.characters.isEmpty && $0.content.characters.count <= 1024 }
    )
    #expect(blocks.reduce(into: AttributedString()) { $0.append($1.content) } == original)
    #expect(blocks.dropLast().allSatisfy { $0.content.characters.last?.isNewline == true })
    #expect(blocks.dropLast().allSatisfy { $0.continuesOnNextBlock })
    #expect(blocks.last?.continuesOnNextBlock == false)
    for block in blocks.dropLast() {
      #expect(String(block.content.characters.dropLast()) == String(block.text.characters))
    }
  }

  @Test("a single linked paragraph splits without breaking graphemes or attributes")
  func hugeParagraphWithUnicodeAndLink() async throws {
    let words = String(repeating: "👩🏽‍💻é🇯🇵", count: 10_000)
    let html = "<p><a href=\"https://example.com\"><b><i>\(words)</i></b></a></p>"
    let blocks = await HTMLContent.descriptionBlocks(html: html, font: .body, linkTimestamps: true)
    let original = try #require(HTMLContent.attributedString(html: html, font: .body))
    #expect(blocks.count > 1)
    #expect(blocks.allSatisfy { $0.content.characters.count <= 1024 })
    #expect(blocks.reduce(into: AttributedString()) { $0.append($1.content) } == original)
    #expect(blocks.flatMap { Array($0.content.characters) } == Array(words))
    #expect(blocks.allSatisfy { $0.text == $0.content })
    #expect(
      blocks.allSatisfy {
        $0.text.runs.allSatisfy { $0.link == URL(string: "https://example.com") }
      }
    )
  }

  @Test(
    "short descriptions retain their exact presentation",
    arguments: [
      "Plain text\n", "<p>One</p><p><b>Two</b></p>", "<ul><li>One</li><li>Two</li></ul>",
    ]
  )
  func shortDescriptions(html: String) async throws {
    let original = try #require(
      await HTMLContent.descriptionAttributedString(html: html, font: .body, linkTimestamps: true)
    )
    let blocks = await HTMLContent.descriptionBlocks(html: html, font: .body, linkTimestamps: true)
    #expect(blocks.count == 1)
    #expect(blocks.first?.text == original)
  }

  @Test("empty descriptions produce no text rows", arguments: ["", "<p></p>"])
  func emptyDescriptions(html: String) async {
    #expect(
      await HTMLContent.descriptionBlocks(html: html, font: .body, linkTimestamps: true) == []
    )
  }

  @Test("timestamp links and external links survive word-boundary splits")
  func timestampsAcrossBlocks() async {
    let html =
      String(repeating: "word ", count: 203)
      + "12:34 <a href=\"https://example.com\">5:30 notes</a> "
      + String(repeating: "word ", count: 300)
    for linkTimestamps in [false, true] {
      let blocks = await HTMLContent.descriptionBlocks(
        html: html,
        font: .body,
        linkTimestamps: linkTimestamps
      )
      let joined = blocks.reduce(into: AttributedString()) { $0.append($1.content) }
      let timestamps = joined.runs.compactMap { run -> String? in
        guard let url = run.link else { return nil }
        return Timestamp.timestamp(fromURL: url)
      }
      #expect(timestamps == (linkTimestamps ? ["12:34"] : []))
      #expect(joined.runs.contains { $0.link == URL(string: "https://example.com") })
      #expect(blocks.dropLast().allSatisfy { $0.content.characters.last?.isWhitespace == true })
    }
  }
}
