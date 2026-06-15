// Copyright Justin Bishop, 2026

import Testing
import UIKit

@testable import PodHaven

@Suite("of LucideIcon tests")
struct LucideIconTests {
  @Test("every icon belongs to exactly one category group")
  func groupsCoverAllCasesUniquely() {
    let grouped = LucideIcon.groups.flatMap { $0.entries.map(\.icon) }
    #expect(grouped.count == LucideIcon.allCases.count)
    #expect(Set(grouped) == Set(LucideIcon.allCases))
  }

  @Test("default icons resolve from their stored rawValues")
  func defaultsResolve() {
    #expect(LucideIcon(rawValue: "tag") == .tag)
    #expect(LucideIcon(rawValue: "list-music") == .listMusic)
  }

  @Test("every icon exposes a non-empty label")
  func everyIconHasLabel() {
    for icon in LucideIcon.allCases {
      #expect(!icon.label.isEmpty)
    }
  }

  @Test("every icon resolves to a bundled LucideIcons asset")
  @MainActor
  func everyIconResolvesToAsset() {
    for icon in LucideIcon.allCases {
      #expect(
        UIImage(named: "LucideIcons/\(icon.rawValue)") != nil,
        "Missing asset for LucideIcon.\(icon.rawValue)"
      )
    }
  }
}
