// Copyright Justin Bishop, 2026

import FactoryKit
import SwiftUI
import Testing
import UIKit

@testable import PodHaven

@Suite("of Sheet alert presentation tests", .container)
@MainActor final class SheetAlertPresentationTests {
  @Observable final class ProbeState {
    var disappearedSheets: [String] = []
    var showsPresenter = true
  }

  private struct ProbeRoot: View {
    @Bindable var alert: PodHaven.Alert
    @Bindable var sheet: PodHaven.Sheet
    @Bindable var state: ProbeState

    var body: some View {
      if state.showsPresenter {
        Text("probe root")
          .customAlert($alert.config, isEnabled: sheet.config == nil)
          .customSheet($sheet.config, alert: $alert.config)
      } else {
        Text("removed")
      }
    }
  }

  private func makeWindow(
    alert: PodHaven.Alert,
    sheet: PodHaven.Sheet,
    state: ProbeState
  ) throws -> UIWindow {
    let host = UIHostingController(rootView: ProbeRoot(alert: alert, sheet: sheet, state: state))
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

  private func cleanUpImmediately(_ window: UIWindow) {
    window.rootViewController?.dismiss(animated: false)
    window.isHidden = true
  }

  private func cleanUp(_ window: UIWindow) async throws {
    window.rootViewController?.dismiss(animated: false)
    try await Wait.until(
      maxAttempts: 400,
      { @MainActor in
        window.rootViewController?.presentedViewController == nil
          && Self.alertController(in: window) == nil
      },
      { @MainActor in "window still had presented content during cleanup" }
    )
    window.isHidden = true
  }

  @Test("custom sheet and alert presentation paths")
  func customSheetPresentation() async throws {
    try await rootAlertPresentsActionsAndDismisses()
    try await alertOverSheetPresents()
    try await sheetDismissalClearsPresentation()
    try await externalSheetDismissalClearsPresentation()
    try await staleSheetConfigClearsWhenPresenterDisappears()
    try await olderSheetDisappearDoesNotClearNewerConfig()
  }

  private func rootAlertPresentsActionsAndDismisses() async throws {
    let alert = Container.shared.alert()
    let sheet = Container.shared.sheet()
    alert.config = nil
    sheet.config = nil
    let window = try makeWindow(alert: alert, sheet: sheet, state: ProbeState())
    defer { cleanUpImmediately(window) }

    alert(title: "Root Probe", "root message") {
      Button("Delete", role: .destructive) {}
      Button("Cancel", role: .cancel) {}
    }

    let alertController = try await Wait.forValue(maxAttempts: 400) { @MainActor in
      Self.alertController(in: window)
    }
    #expect(alertController.title == "Root Probe")
    #expect(alertController.message == "root message")
    #expect(alertController.actions.contains { $0.title == "Delete" && $0.style == .destructive })
    #expect(alertController.actions.contains { $0.title == "Cancel" && $0.style == .cancel })

    alert.config = nil
    try await Wait.until(
      maxAttempts: 400,
      { @MainActor in Self.alertController(in: window) == nil },
      { @MainActor in "root alert never dismissed" }
    )
    try await cleanUp(window)
  }

  private func alertOverSheetPresents() async throws {
    let alert = Container.shared.alert()
    let sheet = Container.shared.sheet()
    alert.config = nil
    sheet.config = nil
    let window = try makeWindow(alert: alert, sheet: sheet, state: ProbeState())
    defer { cleanUpImmediately(window) }

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

    alert.config = nil
    sheet.config = nil
    try await cleanUp(window)
  }

  private func sheetDismissalClearsPresentation() async throws {
    let alert = Container.shared.alert()
    let sheet = Container.shared.sheet()
    alert.config = nil
    sheet.config = nil
    let window = try makeWindow(alert: alert, sheet: sheet, state: ProbeState())
    defer { cleanUpImmediately(window) }

    sheet(id: "probe") { Text("sheet content") }
    try await Wait.until(
      maxAttempts: 400,
      { @MainActor in window.rootViewController?.presentedViewController != nil },
      { @MainActor in "sheet never presented" }
    )

    sheet.dismiss()

    try await Wait.until(
      maxAttempts: 400,
      { @MainActor in window.rootViewController?.presentedViewController == nil },
      { @MainActor in "sheet never dismissed" }
    )
    #expect(sheet.config == nil)
    try await cleanUp(window)
  }

  private func externalSheetDismissalClearsPresentation() async throws {
    let alert = Container.shared.alert()
    let sheet = Container.shared.sheet()
    alert.config = nil
    sheet.config = nil
    let window = try makeWindow(alert: alert, sheet: sheet, state: ProbeState())
    defer { cleanUpImmediately(window) }

    sheet(id: "probe") { Text("sheet content") }
    let presented = try await Wait.forValue(maxAttempts: 400) { @MainActor in
      window.rootViewController?.presentedViewController
    }

    presented.dismiss(animated: false)

    try await Wait.until(
      maxAttempts: 400,
      { @MainActor in window.rootViewController?.presentedViewController == nil },
      { @MainActor in "sheet never dismissed externally" }
    )
    try await Wait.until(
      maxAttempts: 400,
      { @MainActor in sheet.config == nil },
      { @MainActor in "external sheet dismissal did not clear config" }
    )
    try await cleanUp(window)
  }

  private func staleSheetConfigClearsWhenPresenterDisappears() async throws {
    let alert = Container.shared.alert()
    let sheet = Container.shared.sheet()
    alert.config = nil
    sheet.config = nil
    let state = ProbeState()
    let window = try makeWindow(alert: alert, sheet: sheet, state: state)
    defer { cleanUpImmediately(window) }

    sheet(id: "probe") { Text("sheet content") }
    try await Wait.until(
      maxAttempts: 400,
      { @MainActor in window.rootViewController?.presentedViewController != nil },
      { @MainActor in "sheet never presented" }
    )
    #expect(sheet.config != nil)

    state.showsPresenter = false

    try await Wait.until(
      maxAttempts: 400,
      { @MainActor in sheet.config == nil },
      { @MainActor in "stale sheet config was not cleared after presenter disappeared" }
    )
    try await cleanUp(window)
  }

  private func olderSheetDisappearDoesNotClearNewerConfig() async throws {
    let alert = Container.shared.alert()
    let sheet = Container.shared.sheet()
    alert.config = nil
    sheet.config = nil
    let state = ProbeState()
    let window = try makeWindow(alert: alert, sheet: sheet, state: state)
    defer { cleanUpImmediately(window) }

    sheet(id: "first") {
      Text("first sheet")
        .onDisappear { state.disappearedSheets.append("first") }
    }
    try await Wait.until(
      maxAttempts: 400,
      { @MainActor in window.rootViewController?.presentedViewController != nil },
      { @MainActor in "first sheet never presented" }
    )
    let firstConfig = try #require(sheet.config)

    sheet(id: "second") { Text("second sheet") }
    let secondConfig = try #require(sheet.config)
    #expect(secondConfig.id != firstConfig.id)
    #expect(secondConfig.userID == AnyHashable("second"))

    try await Wait.until(
      maxAttempts: 400,
      { @MainActor in state.disappearedSheets.contains("first") },
      { @MainActor in "first sheet content never disappeared" }
    )

    #expect(sheet.config?.id == secondConfig.id)
    #expect(sheet.config?.userID == AnyHashable("second"))

    sheet.config = nil
    try await cleanUp(window)
  }
}
