// Copyright Justin Bishop, 2025

import SwiftUI

typealias PodcastEpisodeListViewModel = SelectableListItemModel<PodcastEpisode>

struct PodcastEpisodeListView: View {
  private let viewModel: PodcastEpisodeListViewModel

  init(viewModel: PodcastEpisodeListViewModel) {
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

#if DEBUG
#Preview {
  @Previewable @State var podcastEpisode: PodcastEpisode?
  @Previewable @State var selectedPodcastEpisode: PodcastEpisode?
  @Previewable @State var isSelected: Bool = false

  List {
    if let podcastEpisode = podcastEpisode {
      PodcastEpisodeListView(
        viewModel: PodcastEpisodeListViewModel(
          isSelected: .constant(false),
          item: podcastEpisode,
          isSelecting: false
        )
      )
    }
    if let selectedPodcastEpisode = selectedPodcastEpisode {
      PodcastEpisodeListView(
        viewModel: PodcastEpisodeListViewModel(
          isSelected: $isSelected,
          item: selectedPodcastEpisode,
          isSelecting: true
        )
      )
    }
  }
  .preview()
  .task {
    podcastEpisode = try? await PreviewHelpers.loadPodcastEpisode()
    selectedPodcastEpisode = try? await PreviewHelpers.loadPodcastEpisode()
  }
}
#endif
