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

  nonisolated private static let log = Log.as(LogSubsystem.PodcastsView.detail)

  init(viewModel: PodcastDetailViewModel) {
    self.viewModel = viewModel
    Self.log.debug("PodcastDetailView init")
  }

  var body: some View {
    contentView
      .toolbar { toolbar }
      .toolbarRole(.editor)
      .sheet(isPresented: $viewModel.showingSettings) {
        if let settings = viewModel.settings {
          PodcastSettingsView(viewModel: viewModel, settings: settings)
        }
      }
      .onChange(of: viewModel.showingSettings) { _, showing in
        if showing {
          Self.log.debug("PodcastSettings sheet presented (podcast: \(viewModel.podcast.toString))")
        } else {
          Self.log.debug("PodcastSettings sheet dismissed (podcast: \(viewModel.podcast.toString))")
        }
      }
      .onAppear {
        Self.log.debug("PodcastDetailView appear")
        viewModel.appear()
      }
      .onDisappear {
        Self.log.debug("PodcastDetailView disappear")
        viewModel.disappear()
      }
      .overlay {
        if showingImageOverlay {
          fullScreenImageOverlay
        }
      }
  }

  private var contentView: some View {
    mainContent
      .safeAreaInset(edge: .top, spacing: 8) {
        headerView
          .padding()
          .glassEffect(in: RoundedRectangle(cornerRadius: 24))
          .padding(.horizontal)
          .dynamicTypeSize(.small ... .xxxLarge)
      }
  }

  @ViewBuilder
  private var mainContent: some View {
    if viewModel.displayingAboutSection {
      expandedAboutInfoView
        .padding(.bottom)
    } else {
      episodeListView
    }
  }

  // MARK: - Toolbar

  @ToolbarContentBuilder
  private var toolbar: some ToolbarContent {
    if viewModel.episodesLoaded
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
            (viewModel.podcast.subscribed ? AppIcon.unsubscribe : AppIcon.subscribe)
              .label("Podcast Actions")
              .labelStyle(.iconOnly)
          }
        )
      }

      if viewModel.saved {
        ToolbarItem(placement: .topBarLeading) {
          AppIcon.settings
            .labelButton {
              viewModel.showingSettings = true
            }
            .buttonStyle(.plain)  // Necessary to keep button coloring after sheet is dismissed
        }
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
      .onTapGesture {
        showingImageOverlay = true
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Show Podcast Artwork")
      .accessibilityHint("Shows the artwork full screen")
      .accessibilityAddTraits(.isButton)
      .accessibilityAction {
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
                .accessibilityHidden(true)
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
    if viewModel.episodesLoaded {
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
            value: Navigation.Destination.listedEpisode(
              episode,
              similarityScore: viewModel.similarityScoreByMediaGUID[episode.mediaGUID]
            ),
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
        .contentMargins(.top, 8, for: .scrollContent)
      } else {
        noEpisodesMessage
      }
    }
    .safeAreaInset(edge: .top, spacing: 0) {
      SearchBar(
        text: $viewModel.filterDebouncer.currentValue,
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
      ProgressView("Loading episodes...")
        .padding()
      Spacer()
    }
  }

  // MARK: - Expanded About

  private var expandedAboutInfoView: some View {
    ScrollView {
      VStack(spacing: 16) {
        metadataRow
          .padding(.horizontal)

        Divider()
          .padding(.horizontal)

        if viewModel.saved {
          TagsView(
            tags: viewModel.tags,
            allTags: viewModel.allTags,
            onAdd: viewModel.addTag,
            onRemove: viewModel.removeTag
          )
          .padding(.horizontal)

          Divider()
            .padding(.horizontal)
        }

        VStack(alignment: .leading, spacing: 16) {
          Text(viewModel.podcast.title)
            .font(.headline)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)

          if let link = viewModel.podcast.link {
            Link(destination: link) {
              HStack(spacing: 16) {
                AppIcon.website.label
                AppIcon.externalLink.image
                  .accessibilityHidden(true)
              }
            }
          }

          descriptionText
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
      }
    }
    .task(id: viewModel.podcast.description) {
      await viewModel.prepareDescription(font: .body)
    }
  }

  @ViewBuilder
  private var descriptionText: some View {
    if let attributed = viewModel.descriptionAttributedString {
      Text(attributed)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  var metadataRow: some View {
    HStack {
      if let cadence = viewModel.resolvedFreshnessCadence {
        FreshnessMetadataItem(
          cadence: cadence,
          value: viewModel.mostRecentEpisodeDate.usShortWithTime,
          style: .detailed
        )
      } else {
        DetailedMetadataItem(
          appIcon: .publishDate,
          value: viewModel.mostRecentEpisodeDate.usShortWithTime
        )
      }

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
            .accessibilityLabel("Podcast Artwork")
            .accessibilityHint("Closes the full-screen artwork")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
              showingImageOverlay = false
            }
        } else {
          VStack(spacing: 16) {
            AppIcon.noImage.image
              .font(.largeTitle)
              .foregroundColor(.secondary)
              .accessibilityHidden(true)

            Text("Image unavailable")
              .font(.title)
              .foregroundColor(.secondary)

            Text("Tap to close")
              .font(.headline)
              .foregroundColor(.secondary)
          }
          .accessibilityElement(children: .ignore)
          .accessibilityLabel("Image unavailable")
          .accessibilityHint("Closes the full-screen artwork")
          .accessibilityAddTraits(.isButton)
          .accessibilityAction {
            showingImageOverlay = false
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
