// Copyright Justin Bishop, 2026

import Foundation
import SwiftUI
import Testing

@testable import PodHaven

@Suite("of HTMLContent review fixes")
struct HTMLContentReviewTests {
  @Test("timestamp URLs require the generated host")
  func timestampURLRequiresGeneratedHost() throws {
    let generated = try #require(Timestamp.url(for: "12:34"))
    #expect(Timestamp.timestamp(fromURL: generated) == "12:34")

    let wrongHost = try #require(URL(string: "podhaven-timestamp://other?t=12:34"))
    #expect(Timestamp.timestamp(fromURL: wrongHost) == nil)
  }

  @Test("anchor href values decode HTML entities before URL creation")
  func anchorHrefDecodesHTMLEntities() throws {
    let html = #"<a href="https://example.com/item?id=123&amp;utm_source=x">Example</a>"#
    let attributed = try #require(HTMLContent.attributedString(html: html, font: .body))
    let expectedURL = try #require(URL(string: "https://example.com/item?id=123&utm_source=x"))

    #expect(link(for: "Example", in: attributed) == expectedURL)
  }

  private func link(for text: String, in attributed: AttributedString) -> URL? {
    for run in attributed.runs where String(attributed[run.range].characters) == text {
      return run.link
    }
    return nil
  }
}
