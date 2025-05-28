// Copyright Justin Bishop, 2025

import SwiftUI

typealias EpisodeResultsListViewModel = SelectableListItemModel<UnsavedEpisode>

struct EpisodeResultsListView: View {
  private let viewModel: EpisodeResultsListViewModel

  init(viewModel: EpisodeResultsListViewModel) {
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

      Text(viewModel.item.title)
        .lineLimit(2)

      Spacer()
    }
  }
}

#if DEBUG
#Preview {
  @Previewable @State var unsavedEpisode: UnsavedEpisode?
  @Previewable @State var selectedUnsavedEpisode: UnsavedEpisode?
  @Previewable @State var isSelected: Bool = false

  List {
    if let unsavedEpisode = unsavedEpisode {
      EpisodeResultsListView(
        viewModel: EpisodeResultsListViewModel(
          isSelected: .constant(false),
          item: unsavedEpisode,
          isSelecting: false
        )
      )
    }
    if let selectedUnsavedEpisode = selectedUnsavedEpisode {
      EpisodeResultsListView(
        viewModel: EpisodeResultsListViewModel(
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
#endif
