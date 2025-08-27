// Copyright Justin Bishop, 2025

import NukeUI
import SwiftUI

struct EpisodeListView<EpisodeType: EpisodeDisplayable>: View {
  private let viewModel: SelectableListItemModel<EpisodeType>

  init(viewModel: SelectableListItemModel<EpisodeType>) {
    self.viewModel = viewModel
  }

  var body: some View {
    HStack(spacing: 4) {
      if viewModel.isSelecting {
        selectionButton
      }
      episodeImage
      statusIconColumn
      episodeInfoSection
    }
    .padding(.bottom, 12)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(Color(uiColor: .separator))
        .frame(height: 0.5)
    }
  }

  var selectionButton: some View {
    Button(
      action: { viewModel.isSelected.wrappedValue.toggle() },
      label: {
        (viewModel.isSelected.wrappedValue
          ? AppLabel.selectionFilled
          : AppLabel.selectionEmpty)
          .image
      }
    )
    .buttonStyle(BorderlessButtonStyle())
  }

  var episodeImage: some View {
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
  }

  var statusIconColumn: some View {
    VStack(spacing: 8) {
      AppLabel.episodeQueued.image
        .font(.caption2)
        .foregroundColor(.orange)
        .opacity(viewModel.item.queued ? 1 : 0)

      AppLabel.episodeCached.image
        .font(.caption2)
        .foregroundColor(.green)
        .opacity(viewModel.item.cached ? 1 : 0)

      AppLabel.episodeCompleted.image
        .font(.caption2)
        .foregroundColor(.blue)
        .opacity(viewModel.item.completed ? 1 : 0)
    }
  }

  var episodeInfoSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(viewModel.item.title)
        .lineLimit(2, reservesSpace: true)
        .font(.body)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .topLeading)

      episodeMetadataRow
    }
  }

  var episodeMetadataRow: some View {
    HStack {
      HStack(spacing: 4) {
        AppLabel.publishDate.image
          .font(.caption2)
          .foregroundColor(.secondary)
        Text(viewModel.item.pubDate.usShort)
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Spacer()

      HStack(spacing: 4) {
        AppLabel.duration.image
          .font(.caption2)
          .foregroundColor(.secondary)
        Text(viewModel.item.duration.shortDescription)
          .font(.caption)
          .foregroundColor(.secondary)
      }
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
      EpisodeListView(
        viewModel: SelectableListItemModel(
          isSelected: .constant(false),
          item: podcastEpisode,
          isSelecting: false
        )
      )
    }
    if let selectedPodcastEpisode {
      EpisodeListView(
        viewModel: SelectableListItemModel(
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
