// Copyright Justin Bishop, 2025

import FactoryKit
import IdentifiedCollections
import SwiftUI

struct SearchView: View {
  @DynamicInjected(\.navigation) private var navigation
  @DynamicInjected(\.sheet) private var sheet

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
    .onAppear { viewModel.appear() }
    .onDisappear { viewModel.disappear() }
  }

  // MARK: - Toolbar

  @ToolbarContentBuilder
  private var toolbar: some ToolbarContent {
    if !viewModel.podcastList.isSelecting {
      ToolbarItem(placement: .topBarLeading) {
        AppIcon.manualEntry.labelButton {
          sheet {
            ManualFeedEntryView(viewModel: ManualFeedEntryViewModel())
          }
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
      if viewModel.podcastList.filteredEntries.isEmpty {
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
      }
    case .error(let message):
      errorView(title: "Unable to Load", message: message)
    }
  }

  // MARK: - Grid & List

  @ViewBuilder
  private var resultsView: some View {
    switch viewModel.displayMode {
    case .grid:
      resultsGrid
    case .list:
      resultsList
    }
  }

  private var resultsGrid: some View {
    ScrollView {
      ItemGrid(items: viewModel.podcastList.filteredEntries) { podcastWithEpisodeMetadata in
        NavigationLink(
          value: Navigation.Destination.podcast(podcastWithEpisodeMetadata.podcast),
          label: {
            PodcastGridView(
              podcast: podcastWithEpisodeMetadata.podcast,
              isSelecting: viewModel.podcastList.isSelecting,
              isSelected: $viewModel.podcastList.isSelected[podcastWithEpisodeMetadata.id]
            )
            .podcastContextMenu(
              viewModel: viewModel,
              podcast: podcastWithEpisodeMetadata.podcast
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
      ForEach(viewModel.podcastList.filteredEntries) { podcastWithEpisodeMetadata in
        NavigationLink(
          value: Navigation.Destination.podcast(podcastWithEpisodeMetadata.podcast),
          label: {
            PodcastListView(
              podcastWithMetadata: podcastWithEpisodeMetadata,
              isSelecting: viewModel.podcastList.isSelecting,
              isSelected: $viewModel.podcastList.isSelected[podcastWithEpisodeMetadata.id]
            )
            .listRowSeparator()
            .podcastContextMenu(
              viewModel: viewModel,
              podcast: podcastWithEpisodeMetadata.podcast
            )
          }
        )
        .listRow()
      }
    }
    .animation(.default, value: viewModel.podcastList.filteredEntries)
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
