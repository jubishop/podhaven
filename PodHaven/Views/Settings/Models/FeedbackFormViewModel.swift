// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import PhotosUI
import Sentry
import SwiftUI
import UIKit

extension Container {
  var captureSentryFeedback: Factory<(SentryFeedback) -> Void> {
    Factory(self) {
      { feedback in
        SentrySDK.capture(feedback: feedback)
      }
    }
    .scope(.cached)
  }
}

@Observable @MainActor class FeedbackFormViewModel {
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.captureSentryFeedback) private var captureSentryFeedback

  var message = ""
  var name = ""
  var email = ""
  let screenshotData = Broadcast<Data?>(nil)

  nonisolated private static let log = Log.as(LogSubsystem.SettingsView.feedback)

  var canSend: Bool {
    !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  func selectedPhotoChanged(_ newItem: PhotosPickerItem?) {
    Task { [weak self, newItem] in
      guard let self else { return }
      do {
        guard let data = try await newItem?.loadTransferable(type: Data.self) else {
          return
        }
        self.screenshotData.new(data)
      } catch {
        Self.log.caughtError("Failed to load selected photo", error)
      }
    }
  }

  func removeScreenshot() {
    screenshotData.new(nil)
  }

  func sendFeedback() {
    var attachments: [Attachment] = [
      Attachment(path: AppInfo.logFileURL.path, filename: "log.ndjson"),
      Attachment(path: WidgetInfo.logFileURL.path, filename: "widget-log.ndjson"),
    ]
    if let data = screenshotData.current,
      let pngData = UIImage(data: data)?.pngData()
    {
      attachments.append(
        Attachment(data: pngData, filename: "screenshot.png", contentType: "image/png")
      )
    }

    captureSentryFeedback(
      SentryFeedback(
        message: message,
        name: name.isEmpty ? nil : name,
        email: email.isEmpty ? nil : email,
        source: .custom,
        attachments: attachments
      )
    )
    alert(title: "Feedback Sent", "Thanks for sending feedback.")
  }
}
