// Copyright Justin Bishop, 2026

import Testing

@testable import PodHaven

@Suite("of accessibility semantics tests", .container)
@MainActor struct AccessibilitySemanticsTests {
  @Test("seek actions include their configured interval")
  func seekActionsIncludeTheirConfiguredInterval() {
    #expect(AppIcon.seekBackward(30).text == "Seek Backward 30 Seconds")
    #expect(AppIcon.seekForward(45).text == "Seek Forward 45 Seconds")
  }
}
