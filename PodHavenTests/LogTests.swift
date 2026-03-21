// Copyright Justin Bishop, 2025

import Testing

@testable import PodHaven

@Suite("of Log tests")
class LogTests {
  @Test("log enum values")
  func logEnumValues() async throws {
    let appDBEnum = LogSubsystem.Database.appDB
    #expect(appDBEnum.subsystem == "Database")
    #expect(appDBEnum.category == "appDB")
  }
}
