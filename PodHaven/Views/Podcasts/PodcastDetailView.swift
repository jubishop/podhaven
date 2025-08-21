// Copyright Justin Bishop, 2025

import FactoryKit
import Logging
import NukeUI
import SwiftUI

struct PodcastDetailView<ViewModel: PodcastDetailViewableModel>: View {
  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.navigation) private var navigation

  @State private var viewModel: ViewModel

  private static var log: Logger { Log.as(LogSubsystem.PodcastsView.detail) }

  init(viewModel: ViewModel) {
    Self.log.debug(
      """
      Showing PodcastDetailView
        viewModel: \(viewModel.podcast.toString)
      """
    )
    self.viewModel = viewModel
  }

  var body: some View {
    VStack(spacing: 4) {
      headerView.padding(.horizontal)
      aboutHeaderView.padding(.horizontal)

      if viewModel.displayAboutSection {
        Divider()
        metadataView.padding(.horizontal)
        Divider()
        expandedAboutInfoView.padding(.horizontal)
      } else {
        episodeListView
      }
    }
    .queueableSelectableEpisodesToolbar(
      viewModel: viewModel,
      episodeList: $viewModel.episodeList,
      selectText: "Select Episodes"
    )
    .task { await viewModel.execute() }
  }

  // MARK: - Header

  private var headerView: some View {
    HStack(alignment: .top, spacing: 12) {
      LazyImage(url: viewModel.podcast.image) { state in
        if let image = state.image {
          image
            .resizable()
            .aspectRatio(contentMode: .fill)
        } else {
          Rectangle()
            .fill(Color.gray.opacity(0.3))
            .overlay(
              VStack {
                Image(systemName: "photo")
                  .foregroundColor(.white.opacity(0.8))
                  .font(.title)
                Text("No Image")
                  .font(.caption)
                  .foregroundColor(.white.opacity(0.8))
              }
            )
        }
      }
      .frame(width: 120, height: 120)
      .clipped()
      .cornerRadius(12)
      .shadow(radius: 4)

      VStack(alignment: .leading, spacing: 8) {
        Text(viewModel.podcast.title)
          .font(.title3)
          .fontWeight(.bold)
          .lineLimit(2, reservesSpace: true)
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)

        if let link = viewModel.podcast.link {
          Link(destination: link) {
            HStack(spacing: 4) {
              Image(systemName: "link")
              Text("Visit Website")
            }
            .font(.caption)
            .foregroundColor(.accentColor)
          }
        }

        if viewModel.subscribable {
          Button(action: {
            if viewModel.podcast.subscribed {
              viewModel.unsubscribe()
            } else {
              viewModel.subscribe()
            }
          }) {
            HStack(spacing: 4) {
              Image(systemName: viewModel.podcast.subscribed ? "minus.circle" : "plus.circle")
              Text(viewModel.podcast.subscribed ? "Unsubscribe" : "Subscribe")
            }
            .font(.caption)
            .foregroundColor(.accentColor)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var aboutHeaderView: some View {
    HStack {
      if viewModel.displayAboutSection {
        Text("About")
          .font(.headline)
          .fontWeight(.semibold)
      } else {
        HStack(spacing: 4) {
          Image(systemName: "calendar")
            .foregroundColor(.secondary)
            .font(.caption)
          Text(viewModel.mostRecentEpisodeDate.usShortWithTime)
            .font(.subheadline)
            .fontWeight(.medium)
        }
      }
      Spacer()
      Button(action: {
        withAnimation(.easeInOut(duration: 0.3)) {
          viewModel.displayAboutSection.toggle()
        }
      }) {
        HStack(spacing: 4) {
          Text(viewModel.displayAboutSection ? "Hide About" : "Show About")
          Image(systemName: viewModel.displayAboutSection ? "chevron.up" : "chevron.down")
        }
        .font(.caption)
        .foregroundColor(.accentColor)
      }
    }
  }

  // MARK: - Episode List

  private var episodeListView: some View {
    VStack {
      EpisodeFilterView(
        entryFilter: $viewModel.episodeList.entryFilter,
        currentFilterMethod: $viewModel.currentFilterMethod
      )
      .padding(.horizontal)

      if viewModel.subscribable {
        if !viewModel.episodeList.filteredEntries.isEmpty {
          episodeList
        } else {
          noEpisodesMessage
        }
      } else {
        loadingEpisodesMessage
      }
    }
  }

  private var episodeList: some View {
    List(viewModel.episodeList.filteredEntries) { episode in
      NavigationLink(
        value: viewModel.navigationDestination(for: episode),
        label: {
          EpisodeListView(
            viewModel: SelectableListItemModel(
              isSelected: $viewModel.episodeList.isSelected[episode],
              item: episode,
              isSelecting: viewModel.episodeList.isSelecting
            )
          )
        }
      )
      .episodeQueueableSwipeActions(viewModel: viewModel, episode: episode)
      .episodeQueueableContextMenu(viewModel: viewModel, episode: episode)
    }
    .conditionalRefreshable(enabled: viewModel.refreshable, action: viewModel.refreshSeries)
    .animation(.default, value: viewModel.episodeList.filteredEntries)
  }

  private var noEpisodesMessage: some View {
    VStack {
      Text("No episodes match the filters.")
        .foregroundColor(.secondary)
        .padding()
      Spacer()
    }
  }

  private var loadingEpisodesMessage: some View {
    VStack {
      Text("Loading episodes...")
        .foregroundColor(.secondary)
        .padding()
      Spacer()
    }
  }

  // MARK: - Expanded About

  private var expandedAboutInfoView: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 8) {
        Text(viewModel.podcast.title)
          .font(.headline)
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity, alignment: .leading)

        HTMLText(viewModel.podcast.description)
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  var metadataView: some View {
    HStack {
      metadataItem(
        icon: "calendar",
        label: "Updated",
        value: viewModel.mostRecentEpisodeDate.usShortWithTime
      )

      Spacer()

      metadataItem(
        icon: "list.bullet",
        label: "Episodes",
        value: "\(viewModel.episodeList.allEntries.count)"
      )
    }
  }

  private func metadataItem(icon: String, label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 4) {
        Image(systemName: icon)
          .foregroundColor(.secondary)
          .font(.caption)
        Text(label)
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Text(value)
        .font(.subheadline)
        .fontWeight(.medium)
    }
  }
}

// MARK: - Preview

#if DEBUG
#Preview("Changelog") {
  @Previewable @State var podcast: Podcast?

  NavigationStack {
    if let podcast {
      PodcastDetailView(viewModel: PodcastDetailViewModel(podcast: podcast))
    }
  }
  .preview()
  .task {
    await PreviewHelpers.dataFetcher
      .respond(
        to: URL(string: "https://changelog.com/podcast/feed")!,
        data: PreviewBundle.loadAsset(named: "changelog", in: .FeedRSS)
      )
    podcast = try? await PreviewHelpers.loadSeries(fileName: "changelog").podcast
  }
}

#Preview("Pod Save America") {
  @Previewable @State var podcast: Podcast?

  NavigationStack {
    if let podcast {
      PodcastDetailView(viewModel: PodcastDetailViewModel(podcast: podcast))
    }
  }
  .preview()
  .task {
    await PreviewHelpers.dataFetcher
      .respond(
        to: URL(string: "https://feeds.simplecast.com/dxZsm5kX")!,
        data: PreviewBundle.loadAsset(named: "pod_save_america", in: .FeedRSS)
      )
    podcast = try? await PreviewHelpers.loadSeries(fileName: "pod_save_america").podcast
  }
}
#endif
