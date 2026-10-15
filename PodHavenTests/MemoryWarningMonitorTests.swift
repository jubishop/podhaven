// Copyright Justin Bishop, 2026

import FactoryKit
import Testing
import UIKit

@testable import PodHaven

@Suite("of MemoryWarningMonitor tests", .container)
@MainActor struct MemoryWarningMonitorTests {
  @Test("memory warnings log below the Sentry warning level")
  func memoryWarningsLogBelowWarning() async throws {
    let message = "System memory warning received"

    let captured = try await LogCapture.withSink { sink in
      Container.shared.memoryWarningMonitor().start()
      Container.shared.notifier()
        .continuation(for: UIApplication.didReceiveMemoryWarningNotification)
        .yield(Notification(name: UIApplication.didReceiveMemoryWarningNotification))
      try await Wait.until(
        { sink.captured().contains { $0.message == message } },
        { "Expected the memory warning to be logged" }
      )
      return sink.captured()
    }

    let warning = try #require(captured.first { $0.message == message })
    #expect(warning.level == .notice)
  }
}
