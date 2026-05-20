// Copyright Justin Bishop, 2026

import PhotosUI
import SwiftUI

struct FeedbackFormView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var viewModel = FeedbackFormViewModel()
  @State private var selectedPhoto: PhotosPickerItem?

  var body: some View {
    let hasScreenshot = viewModel.screenshotData.current != nil

    Form {
      Section {
        TextEditor(text: $viewModel.message)
          .frame(minHeight: 120)
      } footer: {
        Text("Your app logs will be attached automatically.")
      }

      Section {
        if let data = viewModel.screenshotData.current, let uiImage = UIImage(data: data) {
          Image(uiImage: uiImage)
            .resizable()
            .scaledToFit()
            .frame(maxHeight: 200)
            .clipShape(RoundedRectangle(cornerRadius: 8))

          Button("Remove Screenshot", role: .destructive) {
            selectedPhoto = nil
            viewModel.removeScreenshot()
          }
        }

        PhotosPicker(
          selection: $selectedPhoto,
          matching: .images
        ) {
          Label(
            hasScreenshot ? "Replace Screenshot" : "Attach Screenshot",
            systemImage: "photo"
          )
        }
      }

      Section {
        TextField("Name (optional)", text: $viewModel.name)
          .textContentType(.name)
        TextField("Email (optional)", text: $viewModel.email)
          .textContentType(.emailAddress)
          .keyboardType(.emailAddress)
          .textInputAutocapitalization(.never)
      }
    }
    .onChange(of: selectedPhoto) { _, newItem in
      viewModel.selectedPhotoChanged(newItem)
    }
    .navigationTitle("Send Feedback")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("Send") {
          viewModel.sendFeedback()
          dismiss()
        }
        .disabled(!viewModel.canSend)
      }
    }
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
