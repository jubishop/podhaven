// Copyright Justin Bishop, 2026

import Foundation
import SwiftUI
import Testing

@testable import PodHaven

// Each input is large enough that a scan running to the end of the text from
// every candidate position takes minutes of CPU, while a linear pass takes a
// few seconds at most; the budget separates the two.
@Suite("of HTML linear-time tests")
struct HTMLLinearTimeTests {
  private static let budget = Duration.seconds(20)

  @Test("a tag ends before the next opening bracket")
  func tagStopsAtNextOpeningBracket() {
    #expect("1 < 2 <b>bold</b>".strippingHTMLTags() == "1 < 2  bold ")
  }

  @Test("tag stripping is linear in unclosed brackets")
  func strippingUnclosedBrackets() async throws {
    let text = String(repeating: "<", count: 100_000)

    let (stripped, cpu) = try await ThreadCPUTime.measure { text.strippingHTMLTags() }

    #expect(stripped == text)
    #expect(cpu < Self.budget)
  }

  @Test(
    "HTML parsing is linear in pathological descriptions",
    arguments: [
      String(repeating: "<", count: 150_000),
      "<br" + String(repeating: " ", count: 100_000),
      String(repeating: " ", count: 150_000) + "end",
      String(repeating: "<div ", count: 80_000),
      String(repeating: "<p ", count: 130_000),
    ]
  )
  func parsingPathologicalHTML(_ pathology: String) async throws {
    let html = "<b>start</b>" + pathology

    let (attributed, cpu) = try await ThreadCPUTime.measure {
      HTMLContent.attributedString(html: html, font: .body)
    }

    #expect(String(try #require(attributed).characters).hasPrefix("start"))
    #expect(cpu < Self.budget)
  }

  @Test("timestamp linking is linear in timestamps")
  func linkingManyTimestamps() async throws {
    let count = 200_000
    let html = String(repeating: "1:00 ", count: count)

    let (attributed, cpu) = try await ThreadCPUTime.measure {
      await HTMLContent.descriptionAttributedString(html: html, font: .body, linkTimestamps: true)
    }

    #expect(try #require(attributed).runs.count { $0.link != nil } == count)
    #expect(cpu < Self.budget)
  }

  @Test("URL detection is linear in URLs")
  func linkingManyURLs() async throws {
    let count = 150_000
    let html = String(repeating: "http://a.co ", count: count)

    let (attributed, cpu) = try await ThreadCPUTime.measure {
      HTMLContent.attributedString(html: html, font: .body)
    }

    #expect(try #require(attributed).runs.count { $0.link != nil } == count)
    #expect(cpu < Self.budget)
  }
}
