// Copyright Justin Bishop, 2026

import Sentry
import SwiftUI

struct FeedbackFormView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var message = ""
  @State private var name = ""
  @State private var email = ""

  var body: some View {
    Form {
      Section {
        TextEditor(text: $message)
          .frame(minHeight: 120)
      } footer: {
        Text("Your app logs will be attached automatically.")
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
    SentrySDK.capture(
      feedback: .init(
        message: message,
        name: name.isEmpty ? nil : name,
        email: email.isEmpty ? nil : email,
        source: .custom,
        attachments: [
          Attachment(path: AppInfo.logFileURL.path, filename: "log.ndjson"),
          Attachment(path: WidgetInfo.logFileURL.path, filename: "widget-log.ndjson"),
        ]
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
