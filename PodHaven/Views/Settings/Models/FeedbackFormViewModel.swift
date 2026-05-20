// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import PhotosUI
import SwiftUI

@Observable @MainActor class FeedbackFormViewModel {
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.feedbackSender) private var feedbackSender

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
    feedbackSender.send(
      FeedbackReport(
        message: message,
        name: name.isEmpty ? nil : name,
        email: email.isEmpty ? nil : email,
        screenshotData: screenshotData.current
      )
    )
    alert(title: "Feedback Sent", "Thanks for sending feedback.")
  }
}
