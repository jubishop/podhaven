// Copyright Justin Bishop, 2025

import Foundation
import Testing

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

    // Should detect HTML entities
    #expect("Text with &rsquo;quotes&rsquo; here".isHTML() == true)
    #expect("Simple &amp; test".isHTML() == true)

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
  }
}
