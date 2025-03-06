// Copyright Justin Bishop, 2025

import SwiftUI

struct TrendingEpisodeListView: View {
  private let viewModel: TrendingEpisodeListViewModel

  init(viewModel: TrendingEpisodeListViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    Text(viewModel.unsavedEpisode.title)
  }
}

#Preview {
  @Previewable @State var unsavedEpisode: UnsavedEpisode?
  @Previewable @State var selectedUnsavedEpisode: UnsavedEpisode?
  @Previewable @State var isSelected: Bool = false

  List {
    if let unsavedEpisode = unsavedEpisode {
      TrendingEpisodeListView(
        viewModel: TrendingEpisodeListViewModel(
          isSelected: .constant(false),
          unsavedEpisode: unsavedEpisode,
          isSelecting: false
        )
      )
    }
    if let selectedUnsavedEpisode = selectedUnsavedEpisode {
      TrendingEpisodeListView(
        viewModel: TrendingEpisodeListViewModel(
          isSelected: $isSelected,
          unsavedEpisode: selectedUnsavedEpisode,
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
