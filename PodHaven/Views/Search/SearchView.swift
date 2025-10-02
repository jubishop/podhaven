// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct SearchView: View {
  @InjectedObservable(\.navigation) private var navigation
  @InjectedObservable(\.sheet) private var sheet
  @InjectedObservable(\.searchTabViewModel) private var viewModel

  @State private var gridItemSize: CGFloat = 100

  var body: some View {
    IdentifiableNavigationStack(manager: navigation.search) {
      Group {
        if viewModel.isShowingSearchResults {
          searchResultsView
        } else {
          trendingView
        }
      }
      .navigationTitle("Search")
      .toolbar { manualEntryToolbarItem }
    }
    .task(viewModel.loadTrendingIfNeeded)
  }

  // MARK: - Content Builders

  @ViewBuilder
  private var searchResultsView: some View {
    switch viewModel.searchState {
    case .idle:
      placeholderView(
        icon: AppIcon.search,
        title: "Search for podcasts",
        message: "Enter a podcast name or keyword to get started."
      )

    case .loading:
      loadingView(text: "Searching…")

    case .error(let message):
      errorView(title: "Search Error", message: message)

    case .loaded:
      if viewModel.searchResults.isEmpty {
        placeholderView(
          icon: AppIcon.search,
          title: "No results found",
          message: "Try different search terms or check your spelling."
        )
      } else {
        List(viewModel.searchResults, id: \.feedURL) { podcast in
          NavigationLink(
            value: Navigation.Destination.podcast(DisplayedPodcast(podcast)),
            label: { PodcastListView(podcast: podcast) }
          )
        }
        .listStyle(.plain)
      }
    }
  }

  @ViewBuilder
  private var trendingView: some View {
    switch viewModel.trendingState {
    case .idle, .loading:
      loadingView(text: "Fetching top podcasts…")

    case .error(let message):
      errorView(title: "Unable to Load", message: message)

    case .loaded:
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 24) {
          ForEach(viewModel.trendingSections) { section in
            trendingSection(section)
          }
        }
        .padding(.horizontal)
        .padding(.top)
      }
    }
  }

  // MARK: - Section Rendering

  @ViewBuilder
  private func trendingSection(_ section: SearchTabViewModel.TrendingSection) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(section.title)
        .font(.title2.weight(.semibold))

      ItemGrid(items: section.podcasts, minimumGridSize: gridItemSize) { podcast in
        NavigationLink(
          value: Navigation.Destination.podcast(DisplayedPodcast(podcast)),
          label: {
            VStack {
              SquareImage(image: podcast.image, size: $gridItemSize)
              Text(podcast.title)
                .font(.caption)
                .lineLimit(1)
            }
          }
        )
      }
    }
  }

  // MARK: - Toolbar

  @ToolbarContentBuilder
  private var manualEntryToolbarItem: some ToolbarContent {
    ToolbarItem(placement: .primaryAction) {
      Button(action: openManualEntry) {
        Label("Add Feed", systemImage: AppIcon.manualEntry.systemImageName)
      }
      .accessibilityLabel("Add feed URL manually")
    }
  }

  private func openManualEntry() {
    sheet {
      NavigationStack {
        ManualFeedEntryView(viewModel: ManualFeedEntryViewModel())
      }
      .presentationDetents([.medium, .large])
      .presentationDragIndicator(.visible)
    }
  }

  // MARK: - Reusable Views

  private func loadingView(text: String) -> some View {
    VStack(spacing: 16) {
      ProgressView(text)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
  }

  private func placeholderView(icon: AppIcon, title: String, message: String) -> some View {
    VStack(spacing: 16) {
      icon.coloredImage
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

  private func errorView(title: String, message: String) -> some View {
    VStack(spacing: 16) {
      AppIcon.error.coloredImage
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
