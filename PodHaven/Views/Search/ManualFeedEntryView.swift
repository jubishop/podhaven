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

      // Submit Button & Error
      VStack(alignment: .leading, spacing: 16) {
        Button(
          action: {
            isTextFieldFocused = false
            Task {
              if await viewModel.submitURL() {
                dismiss()
              }
            }
          },
          label: {
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
        )
        .buttonStyle(.borderedProminent)
        .disabled(!viewModel.canSubmit)

        // Error Display
        if case .error(let message) = viewModel.state {
          HStack {
            AppIcon.error.image
            Text(message)
              .font(.subheadline)
              .foregroundColor(.red)
          }
        }
      }

      // Preview Section
      switch viewModel.previewState {
      case .idle:
        EmptyView()

      case .loading:
        HStack {
          ProgressView()
          Text("Loading preview...")
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)

      case .loaded(let preview):
        VStack(alignment: .leading, spacing: 12) {
          HStack(spacing: 12) {
            PodLazyImage(url: preview.image) { state in
              if let image = state.image {
                image
                  .resizable()
                  .aspectRatio(contentMode: .fill)
              } else {
                Color.gray.opacity(0.2)
              }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
              Text(preview.title)
                .font(.headline)
                .lineLimit(2)

              if let mostRecentDate = preview.mostRecentPostDate {
                Text("Latest: \(mostRecentDate.formatted(date: .abbreviated, time: .omitted))")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }

              Text("\(preview.episodeCount) episode\(preview.episodeCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()
          }
          .padding()
          .background(Color.gray.opacity(0.1))
          .clipShape(RoundedRectangle(cornerRadius: 12))
        }

      case .error(let message):
        HStack {
          AppIcon.error.image
          Text(message)
            .font(.subheadline)
            .foregroundColor(.red)
        }
      }

      Spacer()
    }
    .padding()
  }
}

// MARK: - Previews

#if DEBUG
#Preview("Manual Feed Entry") {
  ManualFeedEntryView(viewModel: ManualFeedEntryViewModel())
    .preview()
}
#endif
