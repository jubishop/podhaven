// Copyright Justin Bishop, 2026

import SwiftUI
import Testing
import UIKit

@testable import PodHaven

@Observable @MainActor private final class HostedText {
  var value = ""
}

private struct HostedTextView: View {
  let text: HostedText

  var body: some View {
    Text(text.value)
      .font(.largeTitle)
      .foregroundStyle(.black)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(.white)
  }
}

@objc private final class WindowCommand: NSObject {
  @objc let action: Selector?
  @objc let tag = 0

  init(_ action: String) {
    self.action = NSSelectorFromString(action)
  }
}

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

  @Test(
    "hiding the app keeps hosted windows on screen and rendering",
    .enabled(if: ProcessInfo.processInfo.isiOSAppOnMac, "Only an app on a Mac can be hidden")
  )
  func hiddenAppKeepsRendering() async throws {
    let text = HostedText()
    let host = TestHostingController(rootView: HostedTextView(text: text))
    try await withHostedTestWindow(host) { window in
      let application = try #require(macApplication)
      let sceneWindows = try macSceneWindows(of: application)
      try #require(!sceneWindows.isEmpty)
      let blankRendering = try Self.render(window)

      application.perform(NSSelectorFromString("hide:"), with: nil)
      defer { application.perform(NSSelectorFromString("unhideWithoutActivation")) }
      try await Wait.until(
        { @MainActor in application.value(forKey: "isHidden") as? Bool == true },
        { "The app did not hide" }
      )
      #expect(
        sceneWindows.allSatisfy { $0.value(forKey: "isVisible") as? Bool == true },
        "Hiding the app took the hosted scene's window off screen"
      )

      text.value = "Rendered while hidden"
      try await Wait.until(
        { @MainActor in try Self.render(window) != blankRendering },
        { "The hosted view did not render while the app was hidden" }
      )
      #expect(window.windowScene?.activationState == .foregroundActive)
    }
  }

  @Test(
    "hosted scene windows join every Space and can't be minimized",
    .enabled(
      if: ProcessInfo.processInfo.isiOSAppOnMac,
      "Only a Mac window has Spaces and minimizes"
    )
  )
  func sceneWindowsStayOnActiveSpace() async throws {
    let host = TestHostingController(rootView: Text("Scene window availability"))
    try await withHostedTestWindow(host) { _ in
      let sceneWindows = try macSceneWindows(of: try #require(macApplication))
      try #require(!sceneWindows.isEmpty)
      let buttonSelector = NSSelectorFromString("standardWindowButton:")
      let validateSelector = NSSelectorFromString("validateUserInterfaceItem:")
      let miniaturizeButton = 1
      for sceneWindow in sceneWindows {
        let behavior = try #require(sceneWindow.value(forKey: "collectionBehavior") as? UInt)
        #expect(
          behavior & canJoinAllSpaces != 0,
          "Switching Spaces would leave the hosted scene's window behind"
        )

        let standardWindowButton = unsafeBitCast(
          sceneWindow.method(for: buttonSelector),
          to: (@convention(c) (NSObject, Selector, Int) -> NSObject?).self
        )
        let minimizeButton = try #require(
          standardWindowButton(sceneWindow, buttonSelector, miniaturizeButton)
        )
        #expect(
          minimizeButton.value(forKey: "enabled") as? Bool == false,
          "The window's minimize button is enabled"
        )

        let validate = unsafeBitCast(
          sceneWindow.method(for: validateSelector),
          to: (@convention(c) (NSObject, Selector, AnyObject) -> Bool).self
        )
        #expect(
          !validate(sceneWindow, validateSelector, WindowCommand("performMiniaturize:")),
          "The window's Minimize command is enabled"
        )
      }
    }
  }

  private static func render(_ window: UIWindow) throws -> Data {
    let image = UIGraphicsImageRenderer(bounds: window.bounds)
      .image { _ in
        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
      }
    return try #require(image.pngData())
  }
}
