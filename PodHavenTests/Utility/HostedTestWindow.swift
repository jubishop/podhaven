// Copyright Justin Bishop, 2026

import SwiftUI
import Testing
import UIKit

@testable import PodHaven

@MainActor
final class TestHostingController<Content: View>: UIHostingController<Content> {
  let appeared = AsyncLatch<Void>()
  let disappeared = AsyncLatch<Void>()

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    appeared.open()
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    disappeared.open()
  }
}

@MainActor
func withHostedTestWindow<Content: View, Value>(
  _ host: TestHostingController<Content>,
  size: CGSize = CGSize(width: 390, height: 844),
  _ body: @MainActor (UIWindow) async throws -> Value
) async throws -> Value {
  let scene = try #require(
    UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
  )
  let window = UIWindow(windowScene: scene)
  window.frame = CGRect(origin: .zero, size: size)
  window.rootViewController = host
  window.makeKeyAndVisible()
  defer {
    window.isHidden = true
    window.rootViewController = nil
  }
  // Resolve the first layout inside the test's isolated dependency context.
  host.view.layoutIfNeeded()
  try await host.appeared.wait()
  host.view.layoutIfNeeded()

  if ProcessInfo.processInfo.isiOSAppOnMac {
    let address = try #require(
      ProcessInfo.processInfo.environment["PODHAVEN_ACCESSIBILITY_URL"],
      "Run hosted tests with bin/with-test-accessibility xcodebuild test ..."
    )
    var request = URLRequest(url: try #require(URL(string: address)))
    request.httpMethod = "POST"
    request.httpBody = try JSONSerialization.data(
      withJSONObject: ["pid": ProcessInfo.processInfo.processIdentifier]
    )
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 120
    configuration.timeoutIntervalForResource = 120
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let (data, response) = try await session.data(for: request)
    let http = try #require(response as? HTTPURLResponse)
    try #require(http.statusCode == 200, "\(String(decoding: data, as: UTF8.self))")
    host.view.layoutIfNeeded()
  }

  let result: Result<Value, any Error>
  do {
    result = .success(try await body(window))
  } catch {
    result = .failure(error)
  }

  window.isHidden = true
  window.rootViewController = nil
  try await host.disappeared.wait()
  return try result.get()
}

@MainActor
func activateHostedControl(_ element: NSObject) throws {
  if let control = element as? UIControl,
    control.allControlEvents.contains(.primaryActionTriggered)
  {
    control.sendActions(for: .primaryActionTriggered)
  } else {
    try #require(element.accessibilityActivate())
  }
}
