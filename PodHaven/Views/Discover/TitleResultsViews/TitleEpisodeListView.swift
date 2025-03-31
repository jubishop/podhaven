// Copyright Justin Bishop, 2025

import SwiftUI

struct TitleEpisodeListView: View {
  private let viewModel: EpisodeListResultsViewModel

  init(viewModel: EpisodeListResultsViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    HStack(spacing: 20) {
      if viewModel.isSelecting {
        Button(
          action: { viewModel.isSelected.wrappedValue.toggle() },
          label: {
            Image(
              systemName: viewModel.isSelected.wrappedValue
                ? "checkmark.circle.fill" : "circle"
            )
          }
        )
        .buttonStyle(BorderlessButtonStyle())
      }

      Text(viewModel.item.toString)
        .lineLimit(2)

      Spacer()
    }
  }
}

#Preview {
  @Previewable @State var unsavedEpisode: UnsavedEpisode?
  @Previewable @State var selectedUnsavedEpisode: UnsavedEpisode?
  @Previewable @State var isSelected: Bool = false

  List {
    if let unsavedEpisode = unsavedEpisode {
      TitleEpisodeListView(
        viewModel: EpisodeListResultsViewModel(
          isSelected: .constant(false),
          item: unsavedEpisode,
          isSelecting: false
        )
      )
    }
    if let selectedUnsavedEpisode = selectedUnsavedEpisode {
      TitleEpisodeListView(
        viewModel: EpisodeListResultsViewModel(
          isSelected: $isSelected,
          item: selectedUnsavedEpisode,
          isSelecting: true
        )
      )
    }
  }
  .preview()
  .task {
    unsavedEpisode = try? await PreviewHelpers.loadUnsavedEpisode()
    selectedUnsavedEpisode = try? await PreviewHelpers.loadUnsavedEpisode()
  }
}
