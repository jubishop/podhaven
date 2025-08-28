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
      headerView
        .padding(.horizontal)
        .padding(.bottom, 8)

      if viewModel.displayAboutSection {
        expandedAboutInfoView
          .padding(.horizontal)
      } else {
        episodeListView
      }
    }
    .toolbar {
      queueableSelectableEpisodesToolbarItems(
        viewModel: $viewModel,
        episodeList: $viewModel.episodeList,
        selectText: "Select Episodes"
      )

      if !viewModel.isSelecting && viewModel.subscribable
        && !viewModel.podcast.subscribed
      {
        ToolbarItem(placement: .topBarLeading) {
          Button("Subscribe") {
            viewModel.subscribe()
          }
        }
      }
    }
    .toolbarRole(.editor)
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
                AppLabel.noImage.image
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

      VStack(alignment: .leading, spacing: 0) {
        Text(viewModel.podcast.title)
          .font(.title3)
          .fontWeight(.bold)
          .lineLimit(3, reservesSpace: true)
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)

        Spacer()

        Button(action: {
          withAnimation(.easeInOut(duration: 0.3)) {
            viewModel.displayAboutSection.toggle()
          }
        }) {
          HStack(spacing: 6) {
            (viewModel.displayAboutSection
              ? AppLabel.episodesList : AppLabel.aboutInfo)
              .image
            Text(viewModel.displayAboutSection ? "Show Episodes" : "Show Details")
          }
          .font(.subheadline)
          .foregroundColor(.accentColor)
          .padding(.vertical, 8)
          .padding(.horizontal, 4)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: 120, alignment: .leading)
    }
  }

  // MARK: - Episode List

  private var episodeListView: some View {
    VStack {
      episodeFilterView
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

  private var episodeFilterView: some View {
    VStack(spacing: 12) {
      Divider()

      HStack {
        SearchBar(
          text: $viewModel.episodeList.entryFilter,
          placeholder: "Filter episodes",
          imageName: AppLabel.filter.systemImageName
        )

        Menu(
          content: {
            ForEach(EpisodeFilterMethod.allCases, id: \.self) {
              filterMethod in
              Button(filterMethod.rawValue) {
                viewModel.currentFilterMethod = filterMethod
              }
              .disabled(viewModel.currentFilterMethod == filterMethod)
            }
          },
          label: {
            AppLabel.filter.image
          }
        )
      }

      Divider()
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
              isSelecting: viewModel.isSelecting
            )
          )
        }
      )
      .episodeListRow()
      .episodeSwipeActions(viewModel: viewModel, episode: episode)
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
    VStack(spacing: 16) {
      Divider()

      metadataView

      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          // Title
          Text(viewModel.podcast.title)
            .font(.headline)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)

          // Action Links
          VStack(alignment: .leading, spacing: 12) {
            if let link = viewModel.podcast.link {
              Link(destination: link) {
                HStack(spacing: 8) {
                  AppLabel.website.image
                  Text("Visit Website")
                  Spacer()
                  AppLabel.externalLink.image
                }
                .font(.subheadline)
                .foregroundColor(.accentColor)
                .padding(.vertical, 8)
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
                HStack(spacing: 8) {
                  (viewModel.podcast.subscribed ? AppLabel.unsubscribe : AppLabel.subscribe).image
                  Text(viewModel.podcast.subscribed ? "Unsubscribe" : "Subscribe")
                  Spacer()
                }
                .font(.subheadline)
                .foregroundColor(.accentColor)
                .padding(.vertical, 8)
              }
            }
          }
          .padding(.bottom, 8)

          // Description
          HTMLText(viewModel.podcast.description)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  var metadataView: some View {
    HStack {
      metadataItem(
        icon: AppLabel.calendar.systemImageName,
        label: "Updated",
        value: viewModel.mostRecentEpisodeDate.usShortWithTime
      )

      Spacer()

      metadataItem(
        icon: AppLabel.episodes.systemImageName,
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
