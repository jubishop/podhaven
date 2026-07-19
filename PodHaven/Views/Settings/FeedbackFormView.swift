// Copyright Justin Bishop, 2026

import PhotosUI
import SwiftUI

struct FeedbackFormView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var viewModel = FeedbackFormViewModel()
  @State private var selectedPhotos: [PhotosPickerItem] = []

  var body: some View {
    let photos = viewModel.photoData.current
    let hasSelectedPhotos = !selectedPhotos.isEmpty
    let photoPickerLabel = AppIconLabel(
      icon: .attachPhotos,
      textKey: hasSelectedPhotos ? "Edit Photos" : "Attach Photos"
    )

    Form {
      Section {
        TextEditor(text: $viewModel.message)
          .frame(minHeight: 120)
      } footer: {
        Text("Your app logs will be attached automatically.")
      }

      Section {
        ForEach(Array(photos.enumerated()), id: \.offset) { index, data in
          if let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
              .resizable()
              .scaledToFit()
              .frame(maxHeight: 200)
              .clipShape(RoundedRectangle(cornerRadius: 8))
              .accessibilityLabel("Attached photo \(index + 1)")
              .accessibilityValue("\(index + 1) of \(photos.count)")
          }
        }

        if viewModel.isPreparingPhotos {
          ProgressView("Preparing Photos")
        }

        PhotosPicker(
          selection: $selectedPhotos,
          maxSelectionCount: FeedbackFormViewModel.maximumPhotoCount,
          selectionBehavior: .ordered,
          matching: .images
        ) {
          photoPickerLabel
        }

        if hasSelectedPhotos {
          Button("Remove All Photos", role: .destructive) {
            selectedPhotos = []
            viewModel.removePhotos()
          }
        }
      } header: {
        Text("Photos")
      } footer: {
        Text("You can attach up to \(FeedbackFormViewModel.maximumPhotoCount) photos.")
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
    .onChange(of: selectedPhotos) { _, newItems in
      viewModel.selectedPhotosChanged(newItems)
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
