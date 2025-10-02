// Copyright Justin Bishop, 2025

import SwiftUI

struct ManualFeedEntryView: View {
  @Environment(\.dismiss) private var dismiss
  @FocusState private var isTextFieldFocused: Bool
  @State var viewModel: ManualFeedEntryViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      // Instructions
      VStack(alignment: .leading, spacing: 8) {
        Text("Add Feed URL")
          .font(.headline)
        Text("Paste the RSS feed URL of a podcast to subscribe to it directly.")
          .font(.subheadline)
          .foregroundColor(.secondary)
      }
      .padding(.top)

      // URL Input Field
      VStack(alignment: .leading, spacing: 8) {
        Text("Feed URL")
          .font(.subheadline)
          .fontWeight(.medium)

        TextField("Paste entry here.", text: $viewModel.urlText, axis: .vertical)
          .textFieldStyle(.roundedBorder)
          .lineLimit(3...6)
          .keyboardType(.URL)
          .autocorrectionDisabled()
          .textInputAutocapitalization(.never)
          .focused($isTextFieldFocused)
      }

      // Submit Button
      Button(action: {
        isTextFieldFocused = false
        Task {
          if await viewModel.submitURL() {
            dismiss()
          }
        }
      }) {
        HStack {
          if case .loading = viewModel.state {
            ProgressView()
              .scaleEffect(0.8)
          } else {
            AppIcon.subscribe.image
          }
          Text("Add Podcast")
        }
        .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .disabled(!viewModel.canSubmit)

      // Error Display
      if case .error(let message) = viewModel.state {
        HStack {
          AppIcon.error.coloredImage
          Text(message)
            .font(.subheadline)
            .foregroundColor(.red)
        }
        .padding(.top, -8)
      }

      Spacer()
    }
    .padding()
    .navigationTitle("Add Feed URL")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          dismiss()
        }
      }
    }
  }
}

// MARK: - Previews

#if DEBUG
#Preview("Manual Feed Entry") {
  NavigationStack {
    ManualFeedEntryView(viewModel: ManualFeedEntryViewModel())
  }
  .preview()
}
#endif
