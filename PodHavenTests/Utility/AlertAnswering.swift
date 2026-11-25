// Copyright Justin Bishop, 2026

import FactoryKit
import SwiftUI
import Testing
import UIKit

@testable import PodHaven

struct AnsweredAlert {
  let title: String?
  let message: String?
}

private struct AlertPresenter: View {
  @Bindable var alert: PodHaven.Alert

  var body: some View {
    Color.clear.customAlert($alert.config)
  }
}

private typealias AlertActionHandler = @convention(block) (UIAlertAction) -> Void

@MainActor
private func presentedAlertController(in window: UIWindow) -> UIAlertController? {
  var controller = window.rootViewController
  while let presented = controller?.presentedViewController {
    if let alertController = presented as? UIAlertController { return alertController }
    controller = presented
  }
  return nil
}

// Presents the pending alert the way the app does and taps the button titled `buttonTitle`.
@MainActor
@discardableResult
func answerAlert(_ buttonTitle: String) async throws -> AnsweredAlert {
  let alert = Container.shared.alert()
  let host = TestHostingController(rootView: AlertPresenter(alert: alert))
  return try await withHostedTestWindow(host) { window in
    let controller = try await Wait.forValue(maxAttempts: 400) { @MainActor in
      presentedAlertController(in: window)
    }
    let action = try #require(
      controller.actions.first { $0.title == buttonTitle },
      "No \(buttonTitle) button in \(controller.actions.map(\.title))"
    )
    // UIKit can't tap an alert button, so run the handler a tap runs, then dismiss as a tap does.
    let handler = unsafeBitCast(
      try #require(action.value(forKey: "handler") as AnyObject?),
      to: AlertActionHandler.self
    )
    handler(action)
    controller.dismiss(animated: false)
    try await Wait.until(
      maxAttempts: 400,
      { @MainActor in alert.config == nil && presentedAlertController(in: window) == nil },
      { @MainActor in "The \(buttonTitle) button never finished dismissing its alert" }
    )
    return AnsweredAlert(title: controller.title, message: controller.message)
  }
}
