// Copyright Justin Bishop, 2025

import NukeUI
import SwiftUI

typealias PodcastEpisodeListViewModel = SelectableListItemModel<PodcastEpisode>

struct PodcastEpisodeListView: View {
  private let viewModel: PodcastEpisodeListViewModel

  init(viewModel: PodcastEpisodeListViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    HStack(spacing: 12) {
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

      LazyImage(url: viewModel.item.image) { state in
        if let image = state.image {
          image
            .resizable()
            .aspectRatio(contentMode: .fill)
        } else {
          Rectangle()
            .fill(Color.gray.opacity(0.3))
        }
      }
      .frame(width: 60, height: 60)
      .clipped()
      .cornerRadius(8)

      VStack(alignment: .leading, spacing: 4) {
        Text(viewModel.item.episode.title)
          .lineLimit(2)
          .font(.body)
          .multilineTextAlignment(.leading)

        HStack {
          HStack(spacing: 4) {
            Image(systemName: "calendar")
              .font(.caption2)
              .foregroundColor(.secondary)
            Text(viewModel.item.episode.pubDate.usShort)
              .font(.caption)
              .foregroundColor(.secondary)
          }

          Spacer()

          HStack(spacing: 4) {
            Image(systemName: "clock")
              .font(.caption2)
              .foregroundColor(.secondary)
            Text(viewModel.item.episode.duration.shortDescription)
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
      }

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
    if let podcastEpisode {
      PodcastEpisodeListView(
        viewModel: PodcastEpisodeListViewModel(
          isSelected: .constant(false),
          item: podcastEpisode,
          isSelecting: false
        )
      )
    }
    if let selectedPodcastEpisode {
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
