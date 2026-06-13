// Copyright Justin Bishop, 2026

import FactoryKit
import SwiftUI
import Testing
import UIKit

@testable import PodHaven

@Suite("of Sheet alert presentation tests", .container)
@MainActor final class SheetAlertPresentationTests {

  private struct ProbeRoot: View {
    @Bindable var alert: PodHaven.Alert
    @Bindable var sheet: PodHaven.Sheet

    var body: some View {
      Text("probe root")
        .customAlert($alert.config, isEnabled: sheet.config == nil)
        .customSheet($sheet.config, alert: $alert.config)
    }
  }

  private func makeWindow(alert: PodHaven.Alert, sheet: PodHaven.Sheet) throws -> UIWindow {
    let host = UIHostingController(rootView: ProbeRoot(alert: alert, sheet: sheet))
    let scene = try #require(
      UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    )
    let window = UIWindow(windowScene: scene)
    window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
    window.rootViewController = host
    window.makeKeyAndVisible()
    host.view.layoutIfNeeded()
    return window
  }

  private static func alertController(in window: UIWindow) -> UIAlertController? {
    var vc = window.rootViewController
    while let presented = vc?.presentedViewController {
      if let alertVC = presented as? UIAlertController { return alertVC }
      vc = presented
    }
    return nil
  }

  @Test("alert presents while a custom sheet is up")
  func alertOverSheetPresents() async throws {
    let alert = Container.shared.alert()
    let sheet = Container.shared.sheet()
    let window = try makeWindow(alert: alert, sheet: sheet)
    defer { window.isHidden = true }

    sheet(id: "probe") { Text("sheet content") }
    try await Wait.until(
      maxAttempts: 400,
      { @MainActor in window.rootViewController?.presentedViewController != nil },
      { @MainActor in "sheet never presented" }
    )

    alert(title: "Probe", "experiment message") {
      Button("Delete", role: .destructive) {}
      Button("Cancel", role: .cancel) {}
    }

    try await Wait.until(
      maxAttempts: 400,
      { @MainActor in Self.alertController(in: window) != nil },
      { @MainActor in "alert never presented over the sheet" }
    )
  }
}
