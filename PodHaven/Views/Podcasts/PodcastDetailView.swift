// Copyright Justin Bishop, 2025

import FactoryKit
import Logging
import NukeUI
import SwiftUI
import Tagged

struct PodcastDetailView: View {
  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.navigation) private var navigation

  @State private var showingImageOverlay = false
  @State private var viewModel: PodcastDetailViewModel

  private static var log: Logger { Log.as(LogSubsystem.PodcastsView.detail) }

  init(viewModel: PodcastDetailViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    VStack(spacing: 4) {
      headerView
        .padding(.horizontal)
        .padding(.bottom, 8)
        .dynamicTypeSize(.small ... .xxxLarge)

      if viewModel.displayingAboutSection {
        expandedAboutInfoView
          .padding(.bottom)
      } else {
        episodeListView
      }
    }
    .toolbar { toolbar }
    .toolbarRole(.editor)
    .sheet(isPresented: $viewModel.showingSettings) {
      PodcastSettingsView(viewModel: viewModel)
    }
    .onAppear { viewModel.appear() }
    .onDisappear { viewModel.disappear() }
    .overlay {
      if showingImageOverlay {
        fullScreenImageOverlay
      }
    }
  }

  // MARK: - Toolbar

  @ToolbarContentBuilder
  private var toolbar: some ToolbarContent {
    if viewModel.loaded
      && (!viewModel.episodeList.isSelecting || viewModel.displayingAboutSection)
    {
      ToolbarItem(placement: .topBarLeading) {
        Menu(
          content: {
            if viewModel.podcast.subscribed {
              AppIcon.unsubscribe.labelButton {
                viewModel.unsubscribe()
              }
            } else {
              AppIcon.subscribe.labelButton {
                viewModel.subscribe()
              }
            }

            Divider()

            if viewModel.saved {
              AppIcon.delete.labelButton {
                viewModel.delete()
              }
            }
          },
          label: {
            viewModel.podcast.subscribed ? AppIcon.unsubscribe.image : AppIcon.subscribe.image
          }
        )
      }
    }

    if !viewModel.episodeList.isSelecting || viewModel.displayingAboutSection {
      if let shareURL = viewModel.shareURL {
        ToolbarItem(placement: .primaryAction) {
          ShareLink(
            item: shareURL,
            preview: viewModel.sharePreview,
            label: { AppIcon.sharePodcast.label }
          )
        }
      }
    }

    if viewModel.displayingAboutSection && viewModel.saved {
      ToolbarItem(placement: .primaryAction) {
        AppIcon.settings
          .labelButton {
            viewModel.showingSettings = true
          }
          .buttonStyle(.plain)  // Necessary to keep button coloring after sheet is dismissed
      }
    }

    if !viewModel.displayingAboutSection {
      sortableEpisodesToolbarItems(viewModel: viewModel)
      selectableEpisodesToolbarItems(viewModel: viewModel)
    }
  }

  // MARK: - Header

  private var headerView: some View {
    HStack(alignment: .center, spacing: 16) {
      SquareImage(
        image: viewModel.podcast.image,
        cornerRadius: 12,
        size: 128
      )
      .subscriptionBadge(subscribed: viewModel.podcast.subscribed, badgeSize: 20)
      .onTapGesture {
        showingImageOverlay = true
      }

      VStack(alignment: .leading) {
        Text(viewModel.podcast.title)
          .font(.title2)
          .fontWeight(.bold)
          .lineLimit(3, reservesSpace: true)
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity, alignment: .topLeading)

        Spacer(minLength: 4)

        Button(
          action: {
            viewModel.displayingAboutSection.toggle()
            viewModel.episodeList.setSelecting(false)
          },
          label: {
            HStack(spacing: 6) {
              (viewModel.displayingAboutSection ? AppIcon.episodes : AppIcon.aboutInfo).image
              Text(viewModel.displayingAboutSection ? "Show Episodes" : "Show Details")
            }
            .font(.subheadline)
            .foregroundColor(.accentColor)
          }
        )
      }
      .frame(maxWidth: .infinity, minHeight: 128)
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  // MARK: - Episode List

  @ViewBuilder
  private var episodeListView: some View {
    if viewModel.loaded {
      episodeList
    } else {
      loadingEpisodesMessage
    }
  }

  @ViewBuilder
  private var episodeList: some View {
    VStack {
      if !viewModel.episodeList.filteredEntries.isEmpty {
        List(viewModel.episodeList.filteredEntries) { episode in
          NavigationLink(
            value: Navigation.Destination.episode(episode),
            label: {
              EpisodeListView(
                episode: episode,
                isSelecting: viewModel.episodeList.isSelecting,
                isSelected: $viewModel.episodeList.isSelected[episode.id]
              )
              .listRowSeparator()
            }
          )
          .listRow()
          .episodeSwipeActions(viewModel: viewModel, episode: episode)
          .episodeContextMenu(viewModel: viewModel, episode: episode)
        }
      } else {
        noEpisodesMessage
      }
    }
    .safeAreaInset(edge: .top, spacing: 0) {
      SearchBar(
        text: $viewModel.episodeList.entryFilter,
        prompt: "Filter episodes",
        searchIcon: .search
      )
      .padding(.top, 4)
      .padding(.horizontal)
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

      metadataRow
        .padding(.horizontal)

      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          // Title
          Text(viewModel.podcast.title)
            .font(.headline)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)

          // Website Link
          if let link = viewModel.podcast.link {
            Link(destination: link) {
              HStack(spacing: 16) {
                AppIcon.website.label
                AppIcon.externalLink.image
              }
            }
          }

          // Description
          HTMLText(viewModel.podcast.description)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
      }
    }
  }

  var metadataRow: some View {
    HStack {
      DetailedMetadataItem(
        appIcon: .updated,
        value: viewModel.mostRecentEpisodeDate.usShortWithTime
      )

      Spacer()

      DetailedMetadataItem(
        appIcon: .episodeCount,
        value: "\(viewModel.episodeList.allEntries.count)"
      )
    }
    .dynamicTypeSize(.small ... .xxxLarge)
  }

  // MARK: - Full Screen Image Overlay

  private var fullScreenImageOverlay: some View {
    ZStack {
      Color.black
        .opacity(0.92)
        .ignoresSafeArea()

      PipelinedLazyImage(url: viewModel.podcast.image) { state in
        if let image = state.image {
          image
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(4)
        } else {
          VStack(spacing: 16) {
            AppIcon.noImage.image
              .font(.largeTitle)
              .foregroundColor(.secondary)

            Text("Image unavailable")
              .font(.title)
              .foregroundColor(.secondary)

            Text("Tap to close")
              .font(.headline)
              .foregroundColor(.secondary)
          }
        }
      }
    }
    .onTapGesture {
      showingImageOverlay = false
    }
  }
}

// MARK: - Preview

#if DEBUG
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
        PodcastDetailView(
          viewModel: PodcastDetailViewModel(podcast: DisplayedPodcast(unsavedPodcast))
        )
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
