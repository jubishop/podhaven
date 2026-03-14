// Copyright Justin Bishop, 2026

import PhotosUI
import Sentry
import SwiftUI

struct FeedbackFormView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var message = ""
  @State private var name = ""
  @State private var email = ""
  @State private var selectedPhoto: PhotosPickerItem?
  private let screenshotData = Broadcast<Data?>(nil)

  nonisolated private static let log = Log.as(LogSubsystem.SettingsView.feedback)

  var body: some View {
    Form {
      Section {
        TextEditor(text: $message)
          .frame(minHeight: 120)
      } footer: {
        Text("Your app logs will be attached automatically.")
      }

      Section {
        if let data = screenshotData.current, let uiImage = UIImage(data: data) {
          Image(uiImage: uiImage)
            .resizable()
            .scaledToFit()
            .frame(maxHeight: 200)
            .clipShape(RoundedRectangle(cornerRadius: 8))

          Button("Remove Screenshot", role: .destructive) {
            selectedPhoto = nil
            screenshotData.new(nil)
          }
        }

        PhotosPicker(
          selection: $selectedPhoto,
          matching: .images
        ) {
          Label(
            screenshotData.current != nil ? "Replace Screenshot" : "Attach Screenshot",
            systemImage: "photo"
          )
        }
      }

      Section {
        TextField("Name (optional)", text: $name)
          .textContentType(.name)
        TextField("Email (optional)", text: $email)
          .textContentType(.emailAddress)
          .keyboardType(.emailAddress)
          .textInputAutocapitalization(.never)
      }
    }
    .onChange(of: selectedPhoto) { _, newItem in
      Task {
        do {
          guard let data = try await newItem?.loadTransferable(type: Data.self) else {
            return
          }
          screenshotData.new(data)
        } catch {
          Self.log.caughtError("Failed to load selected photo", error)
        }
      }
    }
    .navigationTitle("Send Feedback")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("Send") {
          sendFeedback()
          dismiss()
        }
        .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
  }

  private func sendFeedback() {
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

    SentrySDK.capture(
      feedback: .init(
        message: message,
        name: name.isEmpty ? nil : name,
        email: email.isEmpty ? nil : email,
        source: .custom,
        attachments: attachments
      )
    )
  }
}

#if DEBUG
#Preview {
  NavigationStack {
    FeedbackFormView()
  }
  .preview()
}
#endif
