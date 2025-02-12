// Copyright Justin Bishop, 2025

import SwiftUI

struct EpisodeListView: View {
  @State private var viewModel: EpisodeListViewModel

  init(viewModel: EpisodeListViewModel) {
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

      Text(viewModel.episode.toString)
        .lineLimit(2)

      Spacer()
    }
  }
}

#Preview {
  @Previewable @State var episode: Episode?
  @Previewable @State var selectedEpisode: Episode?
  @Previewable @State var isSelected: Bool = false

  List {
    if let episode = episode {
      EpisodeListView(
        viewModel: EpisodeListViewModel(
          isSelected: .constant(false),
          episode: episode,
          isSelecting: false
        )
      )
    }
    if let selectedEpisode = selectedEpisode {
      EpisodeListView(
        viewModel: EpisodeListViewModel(
          isSelected: $isSelected,
          episode: selectedEpisode,
          isSelecting: true
        )
      )
    }
  }
  .preview()
  .task {
    episode = try? await PreviewHelpers.loadEpisode()
    selectedEpisode = try? await PreviewHelpers.loadEpisode()
  }
}
