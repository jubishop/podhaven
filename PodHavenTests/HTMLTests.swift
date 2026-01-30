// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI
import Testing
import UIKit

@testable import PodHaven

@Suite("of HTML Regex tests", .container)
@MainActor class HTMLTests {
  @Test("that HTML tag detection works")
  func testHTMLTagDetection() throws {
    #expect("Words with <br/> making new lines".hasHTMLTags() == true)
    #expect("Words with <br /> spaced properly".hasHTMLTags() == true)
    #expect("Gotta love <p> for paragraphs</p>".hasHTMLTags() == true)
    #expect("Normal text discussing 1 < 2 and 4 > 3".hasHTMLTags() == false)
    #expect("If you open a tag <p> but don't close it".hasHTMLTags() == true)
    #expect("Hello, world. New stuff! And, commas; too".hasHTMLTags() == false)
  }

  @Test("that isHTML works for both tags and entities")
  func testIsHTML() throws {
    // Should detect HTML tags
    #expect("Words with <br/> making new lines".isHTML() == true)
    #expect("Gotta love <p> for paragraphs</p>".isHTML() == true)
    #expect("Uppercase <BR/> tag".isHTML() == true)
    #expect("Self closing <img/> tag".isHTML() == true)

    // Should detect HTML tags with attributes
    #expect(#"<p class="readrate">Paragraph text"#.isHTML() == true)
    #expect(#"<div id="container">Content</div>"#.isHTML() == true)
    #expect(#"<a href="https://example.com">Link</a>"#.isHTML() == true)
    #expect(#"<img src="image.jpg" alt="description"/>"#.isHTML() == true)
    #expect(#"<p dir="ltr">Directional text"#.isHTML() == true)

    // Should detect HTML entities
    #expect("Text with &rsquo;quotes&rsquo; here".isHTML() == true)
    #expect("Simple &amp; test".isHTML() == true)
    #expect("Entity only &copy;".isHTML() == true)

    // Should detect both
    #expect("<b>Bold</b> with &rsquo;quotes&rsquo;".isHTML() == true)

    // Should not detect plain text
    #expect("Normal text discussing 1 < 2 and 4 > 3".isHTML() == false)
    #expect("I have this & that; nothing special".isHTML() == false)
  }

  @Test("that HTML entity detection works correctly")
  func testHTMLEntityDetection() throws {
    // Should detect named entities
    #expect("Text with &rsquo;quotes&rsquo; here".hasHTMLEntities() == true)
    #expect("Simple &amp; test".hasHTMLEntities() == true)
    #expect("&lt; and &gt; symbols".hasHTMLEntities() == true)

    // Should detect numeric entities
    #expect("Number &#8217; entity".hasHTMLEntities() == true)
    #expect("Hex &#x2019; entity".hasHTMLEntities() == true)

    // Should NOT detect non-entity patterns
    #expect("I have this & that; nothing special".hasHTMLEntities() == false)
    #expect("Price $5 & under; great deal!".hasHTMLEntities() == false)
    #expect("Just regular text here".hasHTMLEntities() == false)
    #expect("Missing semicolon &rsquo here".hasHTMLEntities() == false)
    #expect("Missing ampersand rsquo; here".hasHTMLEntities() == false)
  }

  @Test("that HTML entity decoding works correctly")
  func testHTMLEntityDecoding() throws {
    // Test common entities
    #expect(HTMLText.decodeHTMLEntities("&rsquo;") == "'")
    #expect(HTMLText.decodeHTMLEntities("&lsquo;") == "'")
    #expect(HTMLText.decodeHTMLEntities("&rdquo;") == "\"")
    #expect(HTMLText.decodeHTMLEntities("&ldquo;") == "\"")
    #expect(HTMLText.decodeHTMLEntities("&mdash;") == "—")
    #expect(HTMLText.decodeHTMLEntities("&ndash;") == "–")
    #expect(HTMLText.decodeHTMLEntities("&hellip;") == "…")
    #expect(HTMLText.decodeHTMLEntities("&amp;") == "&")
    #expect(HTMLText.decodeHTMLEntities("&lt;") == "<")
    #expect(HTMLText.decodeHTMLEntities("&gt;") == ">")
    #expect(HTMLText.decodeHTMLEntities("&quot;") == "\"")

    // Test numeric entities
    #expect(HTMLText.decodeHTMLEntities("&#8217;") == "’")  // Right single quotation mark
    #expect(HTMLText.decodeHTMLEntities("&#x2019;") == "’")  // Right single quotation mark (hex)
    #expect(HTMLText.decodeHTMLEntities("&#8212;") == "—")  // Em dash
    #expect(HTMLText.decodeHTMLEntities("&#x2014;") == "—")  // Em dash (hex)

    // Test mixed content
    #expect(
      HTMLText.decodeHTMLEntities("It&rsquo;s &ldquo;amazing&rdquo; &mdash; really!")
        == "It's \"amazing\" — really!"
    )

    // Test multiple entities in one string
    #expect(HTMLText.decodeHTMLEntities("&amp; &lt; &gt; &quot;test&quot;") == "& < > \"test\"")

    // Test case insensitivity
    #expect(HTMLText.decodeHTMLEntities("&RSQUO;") == "'")
    #expect(HTMLText.decodeHTMLEntities("&Mdash;") == "—")
    #expect(HTMLText.decodeHTMLEntities("&#X2019;") == "’")
  }

  @Test("that entity-only strings build attributed output")
  func testEntityOnlyBuildAttributedString() throws {
    let html = "Plain entities: &amp; &lt; &gt; &ldquo;quoted&rdquo; &mdash; no tags."
    guard
      let attributed = HTMLText.buildAttributedStringForTesting(
        html: html,
        font: .body
      )
    else {
      Issue.record("Expected attributed string for entity-only input")
      return
    }

    #expect(String(attributed.characters) == "Plain entities: & < > \"quoted\" — no tags.")
  }

  @Test("that NBSP decodes to a non-breaking space")
  func testNBSPDecoding() throws {
    let html = "A&nbsp;B"
    guard
      let attributed = HTMLText.buildAttributedStringForTesting(
        html: html,
        font: .body
      )
    else {
      Issue.record("Expected attributed string for NBSP entity")
      return
    }

    #expect(String(attributed.characters) == "A\u{00A0}B")
  }

  @Test("that nested formatting keeps expected ranges")
  func testNestedFormatting() throws {
    let html = "<b>bold <i>italic</i> bold</b>"
    guard
      let attributed = HTMLText.buildAttributedStringForTesting(
        html: html,
        font: .body
      )
    else {
      Issue.record("Failed to build attributed string")
      return
    }

    let string = String(attributed.characters)
    #expect(string == "bold italic bold")

    let nsAttributed = NSAttributedString(attributed)
    let expectedItalicRange = (nsAttributed.string as NSString).range(of: "italic")
    #expect(expectedItalicRange.location != NSNotFound)

    var detectedItalic = false

    nsAttributed.enumerateAttributes(in: expectedItalicRange, options: []) { attributes, _, _ in
      let font = attributes[.font] as? UIFont
      if let font {
        #expect(font.fontDescriptor.symbolicTraits.contains(.traitBold))
        if font.fontDescriptor.symbolicTraits.contains(.traitItalic) {
          detectedItalic = true
        }
      }

      if let obliqueness = attributes[.obliqueness] as? NSNumber, obliqueness.doubleValue != 0 {
        detectedItalic = true
      }
    }

    #expect(detectedItalic)
  }

  @Test("that base fonts respect injected font weight")
  func testFontWeightEnvironmentSupport() throws {
    let html = "plain <b>bold</b>"
    let baseFont = Font.system(.title, design: .default).weight(.semibold)
    guard
      let attributed = HTMLText.buildAttributedStringForTesting(
        html: html,
        font: baseFont
      )
    else {
      Issue.record("Failed to build attributed string")
      return
    }

    guard let baseRun = attributed.runs.first else {
      Issue.record("Attributed string unexpectedly empty")
      return
    }

    let baseFontAttribute = baseRun.attributes[AttributeScopes.SwiftUIAttributes.FontAttribute.self]
    #expect(baseFontAttribute == baseFont)

    let boldRun = attributed.runs.first { run in
      let runSubstring = String(attributed[run.range].characters)
      return runSubstring.contains("bold")
    }
    #expect(boldRun != nil)
    let boldFontAttribute = boldRun?
      .attributes[AttributeScopes.SwiftUIAttributes.FontAttribute.self]
    #expect(boldFontAttribute == baseFont.weight(.bold))
  }

  @Test("that environment font scaling is applied")
  func testEnvironmentFontScaling() throws {
    let html = "<b>Scaling</b> check"

    guard
      let bodyAttributed = HTMLText.buildAttributedStringForTesting(html: html, font: .body),
      let largeAttributed = HTMLText.buildAttributedStringForTesting(html: html, font: .largeTitle)
    else {
      Issue.record("Failed to build attributed strings for scaling test")
      return
    }

    let bodyFontAttribute = bodyAttributed.runs.first?
      .attributes[AttributeScopes.SwiftUIAttributes.FontAttribute.self]
    let largeFontAttribute = largeAttributed.runs.first?
      .attributes[AttributeScopes.SwiftUIAttributes.FontAttribute.self]

    #expect(bodyFontAttribute != nil)
    #expect(largeFontAttribute != nil)
    if let bodyFontAttribute, let largeFontAttribute {
      #expect(bodyFontAttribute != largeFontAttribute)
    }
  }

  @Test("that links keep link styling isolated")
  func testLinkStylingIsolation() throws {
    let url = URL(string: "https://example.com")!
    let html = "<a href=\"https://example.com\"><u><b>Bold Link</b></u></a> after"
    guard
      let attributed = HTMLText.buildAttributedStringForTesting(
        html: html,
        font: .body
      )
    else {
      Issue.record("Failed to build attributed string")
      return
    }

    let nsAttributed = NSAttributedString(attributed)
    let linkRange = (nsAttributed.string as NSString).range(of: "Bold Link")
    #expect(linkRange.location != NSNotFound)

    let linkAttribute = nsAttributed.attribute(.link, at: linkRange.location, effectiveRange: nil)
    #expect(linkAttribute as? URL == url)

    if let swiftRange = attributed.range(of: "Bold Link") {
      let linkSlice = attributed[swiftRange]
      #expect(linkSlice.underlineStyle == .single)
    } else {
      Issue.record("Unable to locate 'Bold Link' substring in AttributedString")
    }

    let trailingRange = (nsAttributed.string as NSString).range(of: "after")
    #expect(trailingRange.location != NSNotFound)
    let trailingLink = nsAttributed.attribute(
      .link,
      at: trailingRange.location,
      effectiveRange: nil
    )
    #expect(trailingLink == nil)
  }

  @Test("that strike tags apply strikethrough")
  func testStrikeTagAppliesStrikethrough() throws {
    let html = "<s>Removed</s> text"
    guard
      let attributed = HTMLText.buildAttributedStringForTesting(
        html: html,
        font: .body
      )
    else {
      Issue.record("Failed to build attributed string")
      return
    }

    let nsAttributed = NSAttributedString(attributed)
    let strikeRange = (nsAttributed.string as NSString).range(of: "Removed")
    #expect(strikeRange.location != NSNotFound)
    if let swiftRange = attributed.range(of: "Removed") {
      let strikeSlice = attributed[swiftRange]
      #expect(strikeSlice.strikethroughStyle == .single)
    } else {
      Issue.record("Unable to locate 'Removed' substring in AttributedString")
    }
  }

  @Test("that mark tags apply background highlighting")
  func testMarkTagHighlight() throws {
    let html = "<mark>Important</mark> note"
    guard
      let attributed = HTMLText.buildAttributedStringForTesting(
        html: html,
        font: .body
      )
    else {
      Issue.record("Failed to build attributed string")
      return
    }

    if let swiftRange = attributed.range(of: "Important") {
      let markSlice = attributed[swiftRange]
      #expect(markSlice.backgroundColor != nil)
    } else {
      Issue.record("Unable to locate 'Important' substring in AttributedString")
    }
  }

  @Test("that paragraph preprocessing trims whitespace correctly")
  func testParagraphWhitespaceHandling() throws {
    let html = "  <p>First paragraph.</p>\n\n<p>Second paragraph.</p>   <br/>  Line break.  "
    guard
      let attributed = HTMLText.buildAttributedStringForTesting(
        html: html,
        font: .body
      )
    else {
      Issue.record("Failed to build attributed string")
      return
    }

    let string = String(attributed.characters)
    #expect(
      string
        == """
        First paragraph.

        Second paragraph.

        Line break.
        """
        .trimmingCharacters(in: .whitespacesAndNewlines)
    )
  }

  @Test("that entity decoding leaves invalid items untouched")
  func testEntityDecodingPassThrough() throws {
    let html = "Mix &#65; valid &#12a; hex &#x1F60A; bad &#xZZ;"
    let decoded = HTMLText.decodeHTMLEntities(html)
    #expect(decoded.contains("A"))
    #expect(decoded.contains("😊"))
    #expect(decoded.contains("&#12a;"))
    #expect(decoded.contains("&#xZZ;"))
  }

  @Test("that empty and whitespace HTML yield expected results")
  func testEmptyAndWhitespaceHTML() throws {
    #expect(HTMLText.buildAttributedStringForTesting(html: "", font: .body) == nil)
    #expect(
      HTMLText.buildAttributedStringForTesting(
        html: "   \n\t   ",
        font: .body
      ) == nil
    )
  }

  @Test("that empty tags collapse correctly")
  func testEmptyTags() throws {
    let html = "<p></p><b></b><i></i>"
    let attributed = HTMLText.buildAttributedStringForTesting(
      html: html,
      font: .body
    )
    #expect(attributed?.characters.isEmpty == true)
  }

  @Test("that link URLs preserve original casing")
  func testLinkURLPreservesCasing() throws {
    let html = "<a href=\"https://Example.com/CaseSensitive\">Example</a>"
    guard
      let attributed = HTMLText.buildAttributedStringForTesting(
        html: html,
        font: .body
      )
    else {
      Issue.record("Expected attributed string to be created for anchor tag")
      return
    }

    let nsAttributed = NSAttributedString(attributed)
    let link = nsAttributed.attribute(.link, at: 0, effectiveRange: nil) as? URL

    #expect(link?.absoluteString == "https://Example.com/CaseSensitive")
  }

  @Test("that malformed entities are handled gracefully")
  func testMalformedEntities() throws {
    // Test incomplete entities
    #expect(HTMLText.decodeHTMLEntities("&rsquo") == "&rsquo")  // Missing semicolon
    #expect(HTMLText.decodeHTMLEntities("&unknown;") == "&unknown;")  // Unknown entity

    // Test malformed numeric entities (should be left unchanged)
    #expect(HTMLText.decodeHTMLEntities("&#;") == "&#;")  // Empty numeric entity
    #expect(HTMLText.decodeHTMLEntities("&#abc;") == "&#abc;")  // Invalid numeric entity
    #expect(HTMLText.decodeHTMLEntities("&#x;") == "&#x;")  // Empty hex entity
    #expect(HTMLText.decodeHTMLEntities("&#xzz;") == "&#xzz;")  // Invalid hex entity
    #expect(HTMLText.decodeHTMLEntities("&#9999999;") == "&#9999999;")  // Out of Unicode range
    #expect(HTMLText.decodeHTMLEntities("&#x110000;") == "&#x110000;")  // Above Unicode max
  }

  // MARK: - List Tests

  @Test("that well-formed lists convert to bullets")
  func testWellFormedList() throws {
    let html = "<ul><li>First item</li><li>Second item</li><li>Third item</li></ul>"
    guard
      let attributed = HTMLText.buildAttributedStringForTesting(
        html: html,
        font: .body
      )
    else {
      Issue.record("Failed to build attributed string")
      return
    }

    let string = String(attributed.characters)
    #expect(string.contains("• First item"))
    #expect(string.contains("• Second item"))
    #expect(string.contains("• Third item"))
  }

  @Test("that list items preserve nested formatting tags")
  func testListWithFormattedContent() throws {
    // This test verifies that HTML formatting tags inside list items
    // are preserved and processed correctly. The actual bold/italic rendering
    // is tested in testNestedFormatting; here we just ensure the tags survive
    // list preprocessing.
    let html = "<ul><li><b>Bold</b></li><li><i>Italic</i></li></ul>"
    guard
      let attributed = HTMLText.buildAttributedStringForTesting(
        html: html,
        font: .body
      )
    else {
      Issue.record("Failed to build attributed string")
      return
    }

    let string = String(attributed.characters)
    #expect(string.contains("• Bold"))
    #expect(string.contains("• Italic"))

    // Verify that the attributed string has multiple font runs (indicating formatting was applied)
    #expect(attributed.runs.count > 1)
  }

  @Test("that list items can contain links")
  func testListWithLinks() throws {
    let html = "<ul><li>Item with <a href=\"https://example.com\">link</a></li></ul>"
    guard
      let attributed = HTMLText.buildAttributedStringForTesting(
        html: html,
        font: .body
      )
    else {
      Issue.record("Failed to build attributed string")
      return
    }

    let string = String(attributed.characters)
    #expect(string.contains("• Item with link"))

    let nsAttributed = NSAttributedString(attributed)
    let linkRange = (nsAttributed.string as NSString).range(of: "link")
    #expect(linkRange.location != NSNotFound)

    let linkAttribute = nsAttributed.attribute(.link, at: linkRange.location, effectiveRange: nil)
    #expect(linkAttribute as? URL == URL(string: "https://example.com"))
  }

  @Test("that unclosed list items still convert to bullets")
  func testUnclosedListItems() throws {
    let html = "<ul><li>First item<li>Second item<li>Third item"
    guard
      let attributed = HTMLText.buildAttributedStringForTesting(
        html: html,
        font: .body
      )
    else {
      Issue.record("Failed to build attributed string")
      return
    }

    let string = String(attributed.characters)
    #expect(string.contains("• First item"))
    #expect(string.contains("• Second item"))
    #expect(string.contains("• Third item"))
  }

  @Test("that mixed closed and unclosed list items work")
  func testMixedClosedAndUnclosedListItems() throws {
    let html = "<ul><li>Closed item</li><li>Unclosed item<li>Another closed</li>"
    guard
      let attributed = HTMLText.buildAttributedStringForTesting(
        html: html,
        font: .body
      )
    else {
      Issue.record("Failed to build attributed string")
      return
    }

    let string = String(attributed.characters)
    #expect(string.contains("• Closed item"))
    #expect(string.contains("• Unclosed item"))
    #expect(string.contains("• Another closed"))
  }

  @Test("that orphan list items without ul tags work")
  func testOrphanListItems() throws {
    let html = "<p>Text before</p><li>Orphan item</li><p>Text after</p>"
    guard
      let attributed = HTMLText.buildAttributedStringForTesting(
        html: html,
        font: .body
      )
    else {
      Issue.record("Failed to build attributed string")
      return
    }

    let string = String(attributed.characters)
    #expect(string.contains("Text before"))
    #expect(string.contains("• Orphan item"))
    #expect(string.contains("Text after"))
  }

  @Test("that lists work with surrounding paragraphs")
  func testListInContext() throws {
    let html = "<p>Introduction:</p><ul><li>First</li><li>Second</li></ul><p>Conclusion.</p>"
    guard
      let attributed = HTMLText.buildAttributedStringForTesting(
        html: html,
        font: .body
      )
    else {
      Issue.record("Failed to build attributed string")
      return
    }

    let string = String(attributed.characters)
    #expect(string.contains("Introduction:"))
    #expect(string.contains("• First"))
    #expect(string.contains("• Second"))
    #expect(string.contains("Conclusion."))
  }

  @Test("that lists decode HTML entities correctly")
  func testListWithEntities() throws {
    let html = "<ul><li>Item with &amp; symbol</li><li>Em dash &mdash; here</li></ul>"
    guard
      let attributed = HTMLText.buildAttributedStringForTesting(
        html: html,
        font: .body
      )
    else {
      Issue.record("Failed to build attributed string")
      return
    }

    let string = String(attributed.characters)
    #expect(string.contains("• Item with & symbol"))
    #expect(string.contains("• Em dash — here"))
  }

  @Test("that ordered lists convert to numbered items")
  func testOrderedList() throws {
    let html = "<ol><li>First</li><li>Second</li><li>Third</li></ol>"
    guard
      let attributed = HTMLText.buildAttributedStringForTesting(
        html: html,
        font: .body
      )
    else {
      Issue.record("Failed to build attributed string")
      return
    }

    let string = String(attributed.characters)
    #expect(string.contains("1. First"))
    #expect(string.contains("2. Second"))
    #expect(string.contains("3. Third"))
  }

  @Test("that list items are separated even when missing closing tags")
  func testUnclosedListItemSeparation() throws {
    let html = "<ul><li>First<li>Second<li>Third</ul>"
    guard
      let attributed = HTMLText.buildAttributedStringForTesting(
        html: html,
        font: .body
      )
    else {
      Issue.record("Failed to build attributed string")
      return
    }

    let string = String(attributed.characters)
    let lines = string.components(separatedBy: "\n").filter { !$0.isEmpty }
    #expect(lines.count >= 3)
  }

  @Test("that empty list items are handled")
  func testEmptyListItems() throws {
    let html = "<ul><li></li><li>Content</li><li></li></ul>"
    guard
      let attributed = HTMLText.buildAttributedStringForTesting(
        html: html,
        font: .body
      )
    else {
      Issue.record("Failed to build attributed string")
      return
    }

    let string = String(attributed.characters)
    #expect(string.contains("• Content"))
  }

  // MARK: - Tag Attribute Tolerance

  @Test("that formatting tags with attributes still apply styles")
  func testFormattingTagsWithAttributes() throws {
    let html = "<b class=\"hero\">Bold</b> <i style=\"font-style: italic\">Italic</i>"
    guard
      let attributed = HTMLText.buildAttributedStringForTesting(
        html: html,
        font: .body
      )
    else {
      Issue.record("Failed to build attributed string")
      return
    }

    let boldRun = attributed.runs.first { run in
      String(attributed[run.range].characters).contains("Bold")
    }
    #expect(boldRun != nil)
    let boldFont = boldRun?.attributes[AttributeScopes.SwiftUIAttributes.FontAttribute.self]
    #expect(boldFont == Font.body.weight(.bold))

    let italicRun = attributed.runs.first { run in
      String(attributed[run.range].characters).contains("Italic")
    }
    #expect(italicRun != nil)
    let italicFont = italicRun?.attributes[AttributeScopes.SwiftUIAttributes.FontAttribute.self]
    #expect(italicFont == Font.body.italic())
  }

  @Test("that anchor tags with attributes still resolve links")
  func testAnchorTagWithAttributes() throws {
    let html = "<a class=\"link\" href=\"https://example.com\">Example</a>"
    guard
      let attributed = HTMLText.buildAttributedStringForTesting(
        html: html,
        font: .body
      )
    else {
      Issue.record("Failed to build attributed string")
      return
    }

    let nsAttributed = NSAttributedString(attributed)
    let linkRange = (nsAttributed.string as NSString).range(of: "Example")
    #expect(linkRange.location != NSNotFound)
    let linkAttribute = nsAttributed.attribute(.link, at: linkRange.location, effectiveRange: nil)
    #expect(linkAttribute as? URL == URL(string: "https://example.com"))
  }

  // MARK: - Block Tags

  @Test("that div and heading tags create line breaks")
  func testBlockTagsCreateLineBreaks() throws {
    let html = "<div>Intro</div><h1>Header</h1><div>Body</div>"
    guard
      let attributed = HTMLText.buildAttributedStringForTesting(
        html: html,
        font: .body
      )
    else {
      Issue.record("Failed to build attributed string")
      return
    }

    let string = String(attributed.characters)
    let lines = string.components(separatedBy: "\n").filter { !$0.isEmpty }
    #expect(lines.count == 3)
    #expect(lines[0] == "Intro")
    #expect(lines[1] == "Header")
    #expect(lines[2] == "Body")
  }

  // MARK: - Numeric Entity Recovery

  @Test("that malformed numeric entities do not block later decoding")
  func testMalformedNumericEntityRecovery() throws {
    let html = "Broken &#123 still decodes &#x2019; end"
    let decoded = HTMLText.decodeHTMLEntities(html)
    #expect(decoded.contains("&#123"))
    #expect(decoded.contains("’"))
  }

  @Test("that ul tags without li are stripped cleanly")
  func testUlWithoutLi() throws {
    let html = "<p>Before</p><ul>Just text</ul><p>After</p>"
    guard
      let attributed = HTMLText.buildAttributedStringForTesting(
        html: html,
        font: .body
      )
    else {
      Issue.record("Failed to build attributed string")
      return
    }

    let string = String(attributed.characters)
    #expect(string.contains("Before"))
    #expect(string.contains("Just text"))
    #expect(string.contains("After"))
    #expect(!string.contains("<ul>"))
    #expect(!string.contains("</ul>"))
  }

  // MARK: - Paragraph Tests with Attributes

  @Test("that paragraph tags with attributes are handled correctly")
  func testParagraphTagsWithAttributes() throws {
    let html =
      #"<p class="intro">First paragraph<p class="content">Second paragraph<p id="conclusion">Third paragraph"#
    guard
      let attributed = HTMLText.buildAttributedStringForTesting(
        html: html,
        font: .body
      )
    else {
      Issue.record("Failed to build attributed string")
      return
    }

    let string = String(attributed.characters)

    // Each paragraph should be on a new line
    let lines = string.components(separatedBy: "\n").filter { !$0.isEmpty }
    #expect(lines.count == 3)
    #expect(lines[0].contains("First paragraph"))
    #expect(lines[1].contains("Second paragraph"))
    #expect(lines[2].contains("Third paragraph"))
  }

  @Test("that unclosed paragraph tags with class attributes show line breaks (NPR feed case)")
  func testUnclosedParagraphTagsWithClassAttributes() throws {
    // Real-world example from NPR feed episode 44619c10-6d71-431b-90a6-71951afc14ca
    let html = """
      <p class="readrate">Next year, the Supreme Court will decide whether the President can use a five decade old emergency powers act to shape the U.S. economy.<p class="readrate">Trump invoked the International Emergency Economic Powers Act, or AYEEPA, last spring when he imposed sweeping tariffs of at least 10 percent across all countries.<p class="readrate">Wednesday, the nine justices heard oral arguments in the case.  And however they decide it — the ruling could affect economic policy and presidential power for years to come.
      """

    guard
      let attributed = HTMLText.buildAttributedStringForTesting(
        html: html,
        font: .body
      )
    else {
      Issue.record("Failed to build attributed string")
      return
    }

    let string = String(attributed.characters)

    // Verify line breaks exist between paragraphs
    #expect(string.contains("economy.\n"))
    #expect(string.contains("countries.\n"))

    // Verify content is present
    #expect(string.contains("Supreme Court"))
    #expect(string.contains("AYEEPA"))
    #expect(string.contains("Wednesday"))

    // Verify proper separation - should have multiple lines
    let lines = string.components(separatedBy: "\n").filter { !$0.isEmpty }
    #expect(lines.count >= 3, "Expected at least 3 separate paragraphs")
  }

  @Test("that mixed paragraph tags with and without attributes work together")
  func testMixedParagraphTags() throws {
    let html =
      #"<p>Simple paragraph<p class="highlight">Paragraph with class<p id="footer">Another with id"#
    guard
      let attributed = HTMLText.buildAttributedStringForTesting(
        html: html,
        font: .body
      )
    else {
      Issue.record("Failed to build attributed string")
      return
    }

    let string = String(attributed.characters)

    // All three should be on separate lines
    let lines = string.components(separatedBy: "\n").filter { !$0.isEmpty }
    #expect(lines.count == 3)
    #expect(lines[0] == "Simple paragraph")
    #expect(lines[1] == "Paragraph with class")
    #expect(lines[2] == "Another with id")
  }
}
