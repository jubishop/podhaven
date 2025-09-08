// Copyright Justin Bishop, 2025

import FactoryKit
import NukeUI
import SwiftUI

struct EpisodeListView: View {
  @InjectedObservable(\.playState) private var playState
  @InjectedObservable(\.cacheState) private var cacheState

  private let statusIconFontSize: CGFloat = 12

  private let viewModel: SelectableListItemModel<any EpisodeDisplayable>

  init(viewModel: SelectableListItemModel<any EpisodeDisplayable>) {
    self.viewModel = viewModel
  }

  var body: some View {
    HStack(spacing: 4) {
      if viewModel.isSelecting {
        selectionButton
      }
      episodeImage
      if !viewModel.isSelecting {
        statusIconColumn
      }
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
      if let onDeck = playState.onDeck, onDeck == viewModel.item {
        AppLabel.episodeOnDeck.image
          .foregroundColor(.accentColor)
      } else {
        AppLabel.episodeQueued.image
          .foregroundColor(.orange)
          .opacity(viewModel.item.queued ? 1 : 0)
      }

      if viewModel.item.caching,
        let episodeID = viewModel.item.episodeID
      {
        if let progress = cacheState.progress(episodeID) {
          CircularProgressView(
            colorAmounts: [.green: progress],
            innerRadius: .ratio(0.25)
          )
          .frame(width: statusIconFontSize, height: statusIconFontSize)
        } else {
          AppLabel.waiting.image
            .foregroundColor(.green)
        }
      } else {
        AppLabel.episodeCached.image
          .foregroundStyle(.green)
          .opacity(viewModel.item.cached ? 1 : 0)
      }

      AppLabel.episodeCompleted.image
        .foregroundColor(.blue)
        .opacity(viewModel.item.completed ? 1 : 0)
    }
    .font(.system(size: statusIconFontSize))
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
#Preview("Episode List with Cache States") {
  @Previewable @State var normalEpisode: PodcastEpisode?
  @Previewable @State var cachingEpisode: PodcastEpisode?
  @Previewable @State var cachedEpisode: PodcastEpisode?
  @Previewable @State var isSelected: Bool = false

  List {
    if let normalEpisode {
      EpisodeListView(
        viewModel: SelectableListItemModel(
          isSelected: .constant(false),
          item: normalEpisode,
          isSelecting: false
        )
      )
    }

    if let cachingEpisode {
      EpisodeListView(
        viewModel: SelectableListItemModel(
          isSelected: .constant(false),
          item: cachingEpisode,
          isSelecting: false
        )
      )
    }

    if let cachedEpisode {
      EpisodeListView(
        viewModel: SelectableListItemModel(
          isSelected: $isSelected,
          item: cachedEpisode,
          isSelecting: true
        )
      )
    }
  }
  .preview()
  .task {
    // Load episodes for different states
    normalEpisode = try? await PreviewHelpers.loadPodcastEpisode()
    cachingEpisode = try? await PreviewHelpers.loadPodcastEpisode()
    cachedEpisode = try? await PreviewHelpers.loadPodcastEpisode()

    // Simulate caching progress for the middle episode
    if let episode = cachingEpisode {
      let repo = Container.shared.repo()
      _ = try? await repo.updateDownloadTaskID(episode.id, URLSessionDownloadTask.ID(1))
      cachingEpisode = try? await repo.podcastEpisode(episode.id)
      Container.shared.cacheState()
        .updateProgress(
          for: episode.id,
          progress: 0.65
        )
    }
  }
}
#endif
