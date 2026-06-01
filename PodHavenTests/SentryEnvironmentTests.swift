// Copyright Justin Bishop, 2026

import Sentry
import Testing

@testable import PodHaven

@Suite("of Sentry environment sync tests")
struct SentryEnvironmentTests {
  @Test("structured logs use the current AppInfo environment, not the value frozen at SDK start")
  func sentryLogEnvironmentMatchesAppInfo() throws {
    let prior = AppInfo.environment
    defer { AppInfo.environment = prior }

    AppInfo.environment = .testFlight
    let log = SentryLog(
      level: .info,
      body: "test",
      attributes: [
        "sentry.environment": SentryLog.Attribute(string: EnvironmentType.deployed.rawValue)
      ]
    )

    let updated = AppLauncher.sentryLogApplyingCurrentEnvironment(log)
    let attribute = try #require(updated.attributes["sentry.environment"])
    #expect(attribute.value as? String == EnvironmentType.testFlight.rawValue)
  }
}
