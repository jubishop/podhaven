// Copyright Justin Bishop, 2025

import FactoryKit
import IdentifiedCollections
import Logging
import SwiftUI

struct SearchView: View {
  nonisolated private static let log = Log.as(LogSubsystem.SearchView.main)

  @DynamicInjected(\.navigation) private var navigation

  @State private var isShowingManualFeedEntry = false
  @State private var viewModel: SearchViewModel

  init(viewModel: SearchViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    NavStack(manager: navigation.search) {
      Group {
        if viewModel.isShowingSearchResults {
          searchResultsView
            .navigationTitle(viewModel.searchedText)
            .refreshable {
              await viewModel.refreshSearch()
            }
        } else {
          VStack {  // Needed so the categoryChipsView has a stable View to Inset
            trendingView
              .refreshable {
                await viewModel.refreshCurrentTrendingSection()
              }
          }
          .safeAreaInset(edge: .top, spacing: 2) {
            categoryChipsView
          }
          .navigationTitle(viewModel.currentTrendingSection.title)
        }
      }
      .toolbar { toolbar }
      .toolbarRole(.editor)
      // Attached to the root content rather than the NavStack so pushed
      // destinations (e.g. SearchDiscoveryListView) don't inherit the
      // search field — otherwise editing the query from a pushed view can
      // invalidate the source the discovery list was instantiated with.
      .searchable(
        text: $viewModel.searchText,
        placement: .automatic,
        prompt: Text("Search podcasts")
      )
      .searchPresentationToolbarBehavior(.avoidHidingContent)
    }
    .onChange(of: isShowingManualFeedEntry) { _, showing in
      if showing {
        Self.log.debug("ManualFeedEntry sheet presented")
      } else {
        Self.log.debug("ManualFeedEntry sheet dismissed")
      }
    }
    .onAppear { viewModel.appear() }
    .onDisappear { viewModel.disappear() }
  }

  // MARK: - Toolbar

  @ToolbarContentBuilder
  private var toolbar: some ToolbarContent {
    if !viewModel.podcastList.isSelecting {
      ToolbarItem(placement: .topBarLeading) {
        AppIcon.manualEntry
          .labelButton {
            isShowingManualFeedEntry = true
          }
          .sheet(isPresented: $isShowingManualFeedEntry) {
            ManualFeedEntryView(viewModel: ManualFeedEntryViewModel())
          }
      }
    }

    sortableDisplayingPodcastsToolbarItems(viewModel: viewModel)
    selectablePodcastsToolbarItems(viewModel: viewModel)
  }

  // MARK: - Trending Chips

  @ViewBuilder
  private var categoryChipsView: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 12) {
        ForEach(viewModel.trendingSections) { section in
          categoryChip(for: section)
        }
      }
      .padding(.horizontal)
    }
  }

  @ViewBuilder
  private func categoryChip(for section: SearchViewModel.TrendingSection) -> some View {
    let isSelected = (section == viewModel.currentTrendingSection)

    Button(
      action: {
        viewModel.showTrendingSection(section)
      },
      label: {
        HStack(spacing: 6) {
          section.icon.image
            .font(.callout)
          Text(section.title)
            .font(.subheadline.weight(isSelected ? .bold : .regular))
        }
        .padding(6)
        .foregroundColor(isSelected ? .accentColor : .primary)
      }
    )
    .buttonStyle(.glass)
    .disabled(isSelected)
    .accessibilityLabel("Select trending section: \(section.title)")
  }

  // MARK: - Result Views

  @ViewBuilder
  private var searchResultsView: some View {
    let state = viewModel.searchState

    switch state {
    case .idle:
      placeholderView(
        icon: .search,
        title: "Search for podcasts",
        message: "Enter a podcast name or keyword to get started."
      )
    case .loading:
      loadingView(text: "Searching for \(viewModel.searchedText)...")
    case .loaded:
      if viewModel.podcastList.allEntries.isEmpty {
        placeholderView(
          icon: .search,
          title: "No results found",
          message: "Try different search terms or check your spelling."
        )
      } else {
        resultsView
      }
    case .error(let message):
      errorView(title: "Search Error", message: message)
    }
  }

  @ViewBuilder
  private var trendingView: some View {
    let section = viewModel.currentTrendingSection
    let state = section.state

    switch state {
    case .idle:
      placeholderView(
        icon: section.icon,
        title: "Fetching top podcasts",
        message: "Fetching top \(section.title) podcasts..."
      )
    case .loading:
      loadingView(text: "Fetching top \(section.title) podcasts...")
    case .loaded:
      if section.results.isEmpty {
        placeholderView(
          icon: section.icon,
          title: "No results found",
          message: "Try a different trending category."
        )
      } else {
        resultsView
          .animation(.default, value: viewModel.podcastList.allEntries)
      }
    case .error(let message):
      errorView(title: "Unable to Load", message: message)
    }
  }

  // MARK: - Grid & List

  private var resultsView: some View {
    Group {
      switch viewModel.displayMode {
      case .grid:
        resultsGrid
      case .list:
        resultsList
      }
    }
    .safeAreaInset(edge: .top, spacing: 0) {
      recommendationBanner
    }
  }

  private var resultsGrid: some View {
    ScrollView {
      ItemGrid(items: viewModel.podcastList.allEntries, id: \.podcast.slotID) {
        podcastWithEpisodeMetadata in
        NavigationLink(
          value: Navigation.Destination.listedPodcast(podcastWithEpisodeMetadata.podcast),
          label: {
            PodcastGridView(
              podcast: podcastWithEpisodeMetadata.podcast,
              isSelecting: viewModel.podcastList.isSelecting,
              isSelected: $viewModel.podcastList.isSelected[podcastWithEpisodeMetadata.id]
            )
            .podcastContextMenu(
              viewModel: viewModel,
              podcastWithMetadata: podcastWithEpisodeMetadata
            )
          }
        )
        .buttonStyle(.plain)
      }
      .padding(.horizontal)
    }
  }

  private var resultsList: some View {
    List {
      ForEach(viewModel.podcastList.allEntries, id: \.podcast.slotID) {
        podcastWithEpisodeMetadata in
        NavigationLink(
          value: Navigation.Destination.listedPodcast(podcastWithEpisodeMetadata.podcast),
          label: {
            PodcastListView(
              podcastWithMetadata: podcastWithEpisodeMetadata,
              isSelecting: viewModel.podcastList.isSelecting,
              isSelected: $viewModel.podcastList.isSelected[podcastWithEpisodeMetadata.id]
            )
            .listRowSeparator()
            .podcastSwipeActions(
              viewModel: viewModel,
              podcast: podcastWithEpisodeMetadata.podcast
            )
            .podcastContextMenu(
              viewModel: viewModel,
              podcastWithMetadata: podcastWithEpisodeMetadata
            )
          }
        )
        .listRow()
      }
    }
  }

  // MARK: - Recommendation Banner

  @ViewBuilder
  private var recommendationBanner: some View {
    let collector = viewModel.recommendationCollector
    if let source = collector.activeSource {
      switch collector.bannerState {
      case .hidden:
        EmptyView()
      case .loading:
        bannerStrip(source: source, text: loadingBannerCopy(for: source), tappable: false)
      case .loaded(let count):
        bannerStrip(
          source: source,
          text: loadedBannerCopy(for: source, count: count),
          tappable: true
        )
      }
    }
  }

  @ViewBuilder
  private func bannerStrip(
    source: SearchRecommendationCollector.Source,
    text: String,
    tappable: Bool
  ) -> some View {
    Group {
      if tappable {
        Button {
          navigation.showSearchDiscovery(
            viewModel: SearchDiscoveryListViewModel(
              collector: viewModel.recommendationCollector,
              source: source
            )
          )
        } label: {
          bannerLabel(text: text, showsChevron: true)
        }
        .buttonStyle(.glass)
      } else {
        bannerLabel(text: text, showsChevron: false)
          .glassEffect()
      }
    }
    .padding(.horizontal)
    .padding(.top, 2)
    .padding(.bottom, 6)
  }

  private func bannerLabel(text: String, showsChevron: Bool) -> some View {
    HStack(spacing: 6) {
      Text(text)
        .font(.subheadline.weight(.semibold))
        .foregroundColor(.primary)
        .lineLimit(1)
      Spacer(minLength: 8)
      if showsChevron {
        AppIcon.navigateInto.image
          .font(.subheadline.weight(.semibold))
          .foregroundColor(.accentColor)
      }
    }
    .padding(.horizontal)
    .padding(.vertical, 10)
  }

  private func loadingBannerCopy(for source: SearchRecommendationCollector.Source) -> String {
    switch source {
    case .search(let query):
      return "Finding top picks from \"\(query)\"..."
    case .trending(let trending):
      if trending.genreID == nil { return "Finding top picks..." }
      return "Finding top picks from \(trending.title)..."
    }
  }

  private func loadedBannerCopy(
    for source: SearchRecommendationCollector.Source,
    count: Int
  ) -> String {
    switch source {
    case .search(let query):
      return count == 1 ? "Top pick from \"\(query)\"" : "Top \(count) from \"\(query)\""
    case .trending(let trending):
      if trending.genreID == nil {
        return count == 1 ? "Top pick" : "Top \(count) picks"
      }
      return count == 1
        ? "Top pick from \(trending.title)" : "Top \(count) from \(trending.title)"
    }
  }

  // MARK: - Reusable Views

  private func loadingView(text: String) -> some View {
    ScrollView {
      ProgressView(text)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .center)
    }
  }

  private func placeholderView(icon: AppIcon, title: String, message: String) -> some View {
    ScrollView {
      VStack(spacing: 16) {
        icon.image
          .font(.system(size: 48))
        Text(title)
          .font(.headline)
        Text(message)
          .font(.subheadline)
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func errorView(title: String, message: String) -> some View {
    placeholderView(icon: AppIcon.error, title: title, message: message)
  }
}

// MARK: - Preview

#if DEBUG
#Preview("Trending") {
  SearchPreview(serveFeeds: false, seedRecommendations: false)
}

// Seeds a scoring context and serves synthetic feeds so the discovery banner
// reaches its loaded state (tappable, with chevron) instead of staying on
// "Finding top picks…".
#Preview("Top Picks Loaded") {
  SearchPreview(serveFeeds: true, seedRecommendations: true)
}

private struct SearchPreview: View {
  let serveFeeds: Bool
  let seedRecommendations: Bool

  @State private var isSetupComplete = false

  var body: some View {
    Group {
      if isSetupComplete {
        SearchView(viewModel: SearchViewModel())
      } else {
        ProgressView("Setting up preview…")
      }
    }
    .preview()
    .task {
      await configureSearchPreviewDataFetcher(serveFeeds: serveFeeds)
      if seedRecommendations {
        do {
          try await PreviewRecommendations.seedScoringContext()
        } catch {
          print("Preview error: \(error)")
        }
      }
      isSetupComplete = true
    }
  }
}

@MainActor
private func configureSearchPreviewDataFetcher(serveFeeds: Bool) async {
  let topTechnologyFeed = PreviewBundle.loadAsset(named: "top_technology_feed", in: .iTunesResults)
  let topLookup = PreviewBundle.loadAsset(named: "top_technology_lookup", in: .iTunesResults)
  let searchTechnology = PreviewBundle.loadAsset(named: "search_technology", in: .iTunesResults)

  await PreviewHelpers.dataFetcher.setDefaultHandler { url in
    if url.path.contains("/rss/toppodcasts") {
      return (topTechnologyFeed, URL.response(url))
    } else if url.path.contains("/lookup") {
      return (topLookup, URL.response(url))
    } else if url.path.contains("/search") {
      return (searchTechnology, URL.response(url))
    } else if serveFeeds {
      return (PreviewFeed.rss(for: url), URL.response(url))
    } else {
      return (url.dataRepresentation, URL.response(url))
    }
  }

  let allThumbnails = PreviewBundle.loadAllThumbnails()
  Container.shared.fakeDataLoader()
    .setDefaultHandler { _ in
      allThumbnails.values.randomElement()!.data
    }
}
#endif
