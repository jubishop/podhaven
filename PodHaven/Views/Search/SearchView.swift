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
          .safeAreaInset(edge: .top, spacing: 12) {
            categoryChipsView
          }
          .navigationTitle(viewModel.currentTrendingSection.title)
        }
      }
      .toolbar { toolbar }
      .toolbarRole(.editor)
    }
    .searchable(
      text: $viewModel.searchText,
      placement: .automatic,
      prompt: Text("Search podcasts")
    )
    .searchPresentationToolbarBehavior(.avoidHidingContent)
    .environment(viewModel.recommendationCollector)
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

  @ViewBuilder
  private var resultsView: some View {
    VStack(spacing: 0) {
      recommendationBanner
      switch viewModel.displayMode {
      case .grid:
        resultsGrid
      case .list:
        resultsList
      }
    }
  }

  // MARK: - Recommendation Banner

  @ViewBuilder
  private var recommendationBanner: some View {
    let collector = viewModel.recommendationCollector
    switch collector.bannerState {
    case .hidden:
      EmptyView()
    case .loading:
      bannerStrip(text: loadingBannerCopy, tappable: false)
    case .loaded(let count):
      bannerStrip(text: loadedBannerCopy(count: count), tappable: true)
    }
  }

  @ViewBuilder
  private func bannerStrip(text: String, tappable: Bool) -> some View {
    if tappable, let source = recommendationBannerSource {
      Button {
        navigation.search.path.append(.searchDiscovery(source))
      } label: {
        bannerLabel(text: text, showsChevron: true)
      }
      .buttonStyle(.plain)
    } else {
      bannerLabel(text: text, showsChevron: false)
    }
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
    .background(Color.secondary.opacity(0.08))
  }

  private var recommendationBannerSource: SearchRecommendationCollector.Source? {
    if viewModel.isShowingSearchResults {
      let trimmed = viewModel.searchedText.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return nil }
      return .search(query: trimmed)
    }
    let section = viewModel.currentTrendingSection
    return .trending(genreID: section.genreID, title: section.title)
  }

  private var loadingBannerCopy: String {
    if viewModel.isShowingSearchResults {
      let trimmed = viewModel.searchedText.trimmingCharacters(in: .whitespacesAndNewlines)
      return "Finding top picks from \"\(trimmed)\"..."
    }
    let section = viewModel.currentTrendingSection
    if section.genreID == nil { return "Finding top picks..." }
    return "Finding top picks from \(section.title)..."
  }

  private func loadedBannerCopy(count: Int) -> String {
    if viewModel.isShowingSearchResults {
      let trimmed = viewModel.searchedText.trimmingCharacters(in: .whitespacesAndNewlines)
      return "Top \(count) from \"\(trimmed)\""
    }
    let section = viewModel.currentTrendingSection
    if section.genreID == nil { return "Top \(count) picks" }
    return "Top \(count) from \(section.title)"
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
#Preview {
  @Previewable @State var isSetupComplete = false

  Group {
    if isSetupComplete {
      SearchView(viewModel: SearchViewModel())
        .preview()
    } else {
      ProgressView("Setting up preview…")
    }
  }
  .task {
    // Load sample data
    let topTechnologyFeed = PreviewBundle.loadAsset(
      named: "top_technology_feed",
      in: .iTunesResults
    )
    let topLookup = PreviewBundle.loadAsset(named: "top_technology_lookup", in: .iTunesResults)
    let searchTechnology = PreviewBundle.loadAsset(named: "search_technology", in: .iTunesResults)

    // Configure default handler for all iTunes requests
    await PreviewHelpers.dataFetcher.setDefaultHandler { url in
      // Determine request type by URL path and return appropriate data
      if url.path.contains("/rss/toppodcasts") {
        // Any top podcasts request (any genre or no genre)
        return (topTechnologyFeed, URL.response(url))
      } else if url.path.contains("/lookup") {
        // Any lookup request
        return (topLookup, URL.response(url))
      } else if url.path.contains("/search") {
        // Any search request
        return (searchTechnology, URL.response(url))
      } else {
        // Fallback for unknown requests
        return (url.dataRepresentation, URL.response(url))
      }
    }

    // Configure image loader to return random image
    let allThumbnails = PreviewBundle.loadAllThumbnails()
    Container.shared.fakeDataLoader()
      .setDefaultHandler { url in
        allThumbnails.values.randomElement()!.data
      }

    isSetupComplete = true
  }
}
#endif
