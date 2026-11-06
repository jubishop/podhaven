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

// UIKit doesn't expose the AppKit application and windows that host an iOS app on a Mac.
@MainActor
var macApplication: NSObject? {
  (NSClassFromString("NSApplication") as? NSObject.Type)?.value(forKey: "sharedApplication")
    as? NSObject
}

@MainActor
func macSceneWindows(of application: NSObject) throws -> [NSObject] {
  let sceneWindowClass: AnyClass = try #require(NSClassFromString("UINSWindow"))
  let windows = try #require(application.value(forKey: "windows") as? [NSObject])
  return windows.filter { $0.isKind(of: sceneWindowClass) }
}

// On a Mac, hiding the app or minimizing its window moves the scene to the background, where
// SwiftUI stops updating hosted views. Keep the window on screen while the app is hidden, and
// bring it back without activating the app if it already left.
@MainActor
func keepTestSceneOnScreen(_ scene: UIWindowScene) async throws {
  guard let application = macApplication else { return }
  let windows = try macSceneWindows(of: application)
  for window in windows {
    window.setValue(false, forKey: "canHide")
  }
  guard scene.activationState == .background else { return }
  for window in windows {
    window.perform(NSSelectorFromString("deminiaturize:"), with: nil)
    window.perform(NSSelectorFromString("orderFrontRegardless"))
  }
  try await Wait.until(
    { @MainActor in scene.activationState != .background },
    { "The test host's scene did not return to the foreground" }
  )
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
  try await keepTestSceneOnScreen(scene)
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
