// Copyright Justin Bishop, 2026

import SwiftUI
import Testing
import UIKit

@testable import PodHaven

@Suite("Hosted test window lifecycle", .container)
@MainActor struct HostedTestWindowTests {
  @Test("window scopes finish appearance before inspection and disappearance before returning")
  func balancedLifecycle() async throws {
    let host = TestHostingController(rootView: Text("Hosted lifecycle"))
    try await withHostedTestWindow(host) { window in
      #expect(host.appeared.isOpen)
      #expect(host.view.window === window)
    }
    #expect(host.disappeared.isOpen)
    #expect(host.view.window == nil)
  }

  @Test("throwing inspection still finishes the hosted lifecycle")
  func throwingInspection() async throws {
    let host = TestHostingController(rootView: Text("Throwing inspection"))
    await #expect(throws: TestError.self) {
      try await withHostedTestWindow(host) { _ in
        #expect(host.appeared.isOpen)
        throw TestError.simulatedFailure
      }
    }
    #expect(host.disappeared.isOpen)
    #expect(host.view.window == nil)
  }
}
