// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of Log tests", .container)
class LogTests {
  @Test("log enum values")
  func logEnumValues() async throws {
    let appDBEnum = LogSubsystem.Database.appDB
    #expect(appDBEnum.subsystem == "database")
    #expect(appDBEnum.category == "appDB")
  }
}
