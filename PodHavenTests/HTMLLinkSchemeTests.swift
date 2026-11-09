// Copyright Justin Bishop, 2026

import Foundation
import SwiftUI
import Testing

@testable import PodHaven

@Suite("of HTML link scheme tests")
struct HTMLLinkSchemeTests {
  @Test(
    "anchors with schemes other than web or mail render as plain text",
    arguments: [
      "podhaven://share?url=https://attacker.example/subscribe.opml",
      "podhaven-timestamp://play?t=12:34",
      "tel:+19005551234",
      "sms:+19005551234",
      "facetime:caller@example.com",
      "shortcuts://run-shortcut?name=x",
      "itms-services://?action=download-manifest&amp;url=https://attacker.example/app.plist",
      "javascript:alert(1)",
      "JavaScript:alert(1)",
      "data:text/html,hello",
      "file:///etc/hosts",
      "otherapp://deep/link",
      "/relative/show-notes",
    ]
  )
  func rejectsUnsafeAnchorScheme(href: String) throws {
    let html = #"Before <a href="\#(href)">Show notes</a> after"#
    let attributed = try #require(HTMLContent.attributedString(html: html, font: .body))

    #expect(String(attributed.characters) == "Before Show notes after")
    #expect(attributed.runs.allSatisfy { $0.link == nil })
  }

  @Test(
    "anchors with web or mail schemes stay linked",
    arguments: [
      "https://example.com/notes",
      "http://example.com/notes",
      "HTTPS://Example.com/Notes",
      "mailto:host@example.com",
    ]
  )
  func keepsWebAndMailAnchorScheme(href: String) throws {
    let html = #"Before <a href="\#(href)">Show notes</a> after"#
    let attributed = try #require(HTMLContent.attributedString(html: html, font: .body))
    let expected = try #require(URL(string: href))

    #expect(link(for: "Show notes", in: attributed) == expected)
  }

  @Test("detail descriptions drop unsafe anchors but keep timestamps and web links")
  func detailDescriptionDropsUnsafeAnchors() async throws {
    let html =
      #"<p><a href="tel:+19005551234">Call us</a> at 12:34, "#
      + #"or read <a href="https://example.com">the notes</a>.</p>"#
    let blocks = await HTMLContent.descriptionBlocks(html: html, font: .body, linkTimestamps: true)
    let attributed = blocks.reduce(into: AttributedString()) { $0.append($1.content) }
    let schemes = attributed.runs.compactMap { $0.link?.scheme }

    #expect(link(for: "Call us", in: attributed) == nil)
    #expect(link(for: "the notes", in: attributed) == URL(string: "https://example.com"))
    #expect(schemes.allSatisfy { $0 == "https" || $0 == "podhaven-timestamp" })
    #expect(schemes.contains("podhaven-timestamp"))
  }

  private func link(for text: String, in attributed: AttributedString) -> URL? {
    for run in attributed.runs where String(attributed[run.range].characters) == text {
      return run.link
    }
    return nil
  }
}
