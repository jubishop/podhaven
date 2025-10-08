// Copyright Justin Bishop, 2025

import FactoryKit
import Logging
import SwiftUI

struct PodcastDetailView: View {
  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.navigation) private var navigation

  @State private var viewModel: PodcastDetailViewModel

  private static var log: Logger { Log.as(LogSubsystem.PodcastsView.detail) }

  init(viewModel: PodcastDetailViewModel) {
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
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)

      if viewModel.displayAboutSection {
        expandedAboutInfoView
          .padding(.horizontal)
      } else {
        episodeListView
      }
    }
    .toolbar {
      selectableEpisodesToolbarItems(
        viewModel: viewModel,
        episodeList: viewModel.episodeList,
        selectText: "Select Episodes"
      )

      if !viewModel.isSelecting && viewModel.subscribable {
        if viewModel.podcast.subscribed {
          ToolbarItem(placement: .topBarLeading) {
            HStack(spacing: 4) {
              AppIcon.subscribed.coloredImage
                .font(.system(size: 12))
              Text("Subscribed")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
            }
          }
          .sharedBackgroundVisibility(.hidden)
        } else {
          ToolbarItem(placement: .topBarLeading) {
            Button("Subscribe") {
              viewModel.subscribe()
            }
          }
        }
      }
    }
    .toolbarRole(.editor)
    .task { await viewModel.execute() }
    .onDisappear { viewModel.disappear() }
  }

  // MARK: - Header

  private var headerView: some View {
    HStack(alignment: .top, spacing: 16) {
      PodLazyImage(url: viewModel.podcast.image) { state in
        if let image = state.image {
          image
            .resizable()
            .aspectRatio(contentMode: .fill)
        } else {
          Rectangle()
            .fill(Color.gray.opacity(0.3))
            .overlay(
              VStack {
                AppIcon.noImage.coloredImage
                  .font(.title)
                Text("No Image")
                  .font(.caption)
                  .foregroundColor(.white.opacity(0.8))
              }
            )
        }
      }
      .frame(width: 128, height: 128)
      .clipped()
      .cornerRadius(12)

      VStack(alignment: .leading, spacing: 4) {
        Text(viewModel.podcast.title)
          .font(.title3)
          .fontWeight(.bold)
          .lineLimit(3, reservesSpace: true)
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)

        Spacer()

        Button(
          action: {
            viewModel.displayAboutSection.toggle()
          },
          label: {
            HStack(spacing: 6) {
              (viewModel.displayAboutSection
                ? AppIcon.episodesList : AppIcon.aboutInfo)
                .image
              Text(viewModel.displayAboutSection ? "Show Episodes" : "Show Details")
            }
            .font(.subheadline)
            .foregroundColor(.accentColor)
          }
        )
      }
      .frame(maxWidth: .infinity, idealHeight: 112, maxHeight: 112)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.vertical, 8)
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
          imageName: AppIcon.filter.systemImageName
        )

        Menu(
          content: {
            ForEach(viewModel.allFilterMethods, id: \.self) {
              filterMethod in
              Button(filterMethod.rawValue) {
                viewModel.currentFilterMethod = filterMethod
              }
              .disabled(viewModel.currentFilterMethod == filterMethod)
            }
          },
          label: {
            AppIcon.filter.image
          }
        )
      }

      Divider()
    }
  }

  private var episodeList: some View {
    List(viewModel.episodeList.filteredEntries) { episode in
      NavigationLink(
        value: Navigation.Destination.episode(episode),
        label: {
          EpisodeListView(
            episode: episode,
            isSelecting: viewModel.isSelecting,
            isSelected: $viewModel.episodeList.isSelected[episode.id]
          )
        }
      )
      .episodeListRow()
      .episodeSwipeActions(viewModel: viewModel, episode: episode)
      .episodeContextMenu(viewModel: viewModel, episode: episode)
    }
    .refreshable(action: viewModel.refreshSeries)
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
                  AppIcon.website.image
                  Text("Visit Website")
                  Spacer()
                  AppIcon.externalLink.image
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
                  (viewModel.podcast.subscribed ? AppIcon.unsubscribe : AppIcon.subscribe).image
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
        appIcon: .calendar,
        value: viewModel.mostRecentEpisodeDate.usShortWithTime
      )

      Spacer()

      metadataItem(
        appIcon: .episodes,
        value: "\(viewModel.episodeList.allEntries.count)"
      )
    }
  }

  private func metadataItem(appIcon: AppIcon, value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 4) {
        Image(systemName: appIcon.systemImageName)
          .foregroundColor(.secondary)
          .font(.caption)
        Text(appIcon.text)
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

struct PodcastDetailViewPreview: View {
  @State var unsavedPodcast: UnsavedPodcast?
  @State var path: [UnsavedPodcast] = []

  private let imageURLString: String
  private let imageAssetName: String
  private let assetName: String
  private let feedURLString: String

  init(
    imageURLString: String,
    imageAssetName: String,
    assetName: String,
    feedURLString: String
  ) {
    self.imageURLString = imageURLString
    self.imageAssetName = imageAssetName
    self.assetName = assetName
    self.feedURLString = feedURLString
  }

  var body: some View {
    NavigationStack(path: $path) {
      Button("Go to Podcast") {
        if let unsavedPodcast {
          path = [unsavedPodcast]
        }
      }
      .navigationDestination(for: UnsavedPodcast.self) { unsavedPodcast in
        PodcastDetailView(viewModel: PodcastDetailViewModel(podcast: unsavedPodcast))
      }
    }
    .preview()
    .task {
      guard unsavedPodcast == nil else { return }

      Container.shared.fakeDataLoader()
        .respond(
          to: URL(string: imageURLString)!,
          data: PreviewBundle.loadImageData(
            named: imageAssetName,
            in: .EpisodeThumbnails
          )
        )

      // Configure image loader to return random image
      let allThumbnails = PreviewBundle.loadAllThumbnails()
      Container.shared.fakeDataLoader()
        .setDefaultHandler { url in
          allThumbnails.values.randomElement()!.data
        }

      let data = PreviewBundle.loadAsset(named: assetName, in: .FeedRSS)
      await PreviewHelpers.dataFetcher
        .respond(
          to: URL(string: feedURLString)!,
          data: data
        )

      let podcastFeed = try! await PodcastFeed.parse(
        data,
        from: FeedURL(URL(string: feedURLString)!)
      )
      unsavedPodcast = try! podcastFeed.toUnsavedPodcast()
      if let unsavedPodcast {
        path = [unsavedPodcast]
      }
    }
  }
}
#if DEBUG
#Preview("Changelog") {
  PodcastDetailViewPreview(
    imageURLString:
      "https://cdn.changelog.com/static/images/podcasts/podcast-original-f16d0363067166f241d080ee2e2d4a28.png",
    imageAssetName: "changelog-podcast",
    assetName: "changelog",
    feedURLString: "https://changelog.com/podcast/feed"
  )
}

#Preview("Pod Save America") {
  PodcastDetailViewPreview(
    imageURLString:
      "https://image.simplecastcdn.com/images/9aa1e238-cbed-4305-9808-c9228fc6dd4f/eb7dddd4-ecb0-444c-b379-f75d7dc6c22b/3000x3000/uploads-2f1595947484360-nc4atf9w7ur-dbbaa7ee07a1ee325ec48d2e666ac261-2fpodsave100daysfinal1800.jpg?aid=rss_feed",
    imageAssetName: "pod-save-america-podcast",
    assetName: "pod_save_america",
    feedURLString: "https://feeds.simplecast.com/dxZsm5kX"
  )
}
#endif
