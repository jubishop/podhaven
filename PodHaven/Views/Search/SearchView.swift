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
      .navigationTitle(navigationTitle)
      .toolbar {
        manualEntryToolbarItem
        trendingMenuToolbarItem
      }
    }
    .task(viewModel.loadTrendingIfNeeded)
    .onDisappear { viewModel.disappear() }
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
      if let section = viewModel.selectedTrendingSection {
        ScrollView {
          trendingGrid(for: section)
            .padding(.horizontal)
            .padding(.top)
        }
      } else {
        placeholderView(
          icon: AppIcon.trending,
          title: "No trending podcasts",
          message: "Unable to load curated charts right now."
        )
      }
    }
  }

  // MARK: - Section Rendering

  @ViewBuilder
  private func trendingSelectionMenu(selected section: SearchTabViewModel.TrendingSection)
    -> some View
  {
    Menu {
      ForEach(viewModel.trendingSections) { option in
        option.icon.labelButton {
          viewModel.selectTrendingSection(option.id)
        }
      }
    } label: {
      section.icon.coloredLabel
        .font(.title2.weight(.semibold))
    }
  }

  @ViewBuilder
  private func trendingGrid(for section: SearchTabViewModel.TrendingSection) -> some View {
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
      .buttonStyle(.plain)
    }
  }

  // MARK: - Toolbar

  @ToolbarContentBuilder
  private var manualEntryToolbarItem: some ToolbarContent {
    ToolbarItem(placement: .navigationBarLeading) {
      Button(action: openManualEntry) {
        Label("Add Feed", systemImage: AppIcon.manualEntry.systemImageName)
      }
      .accessibilityLabel("Add feed URL manually")
    }
  }

  @ToolbarContentBuilder
  private var trendingMenuToolbarItem: some ToolbarContent {
    if !viewModel.isShowingSearchResults,
      viewModel.trendingState == .loaded,
      let section = viewModel.selectedTrendingSection
    {
      ToolbarItem(placement: .primaryAction) {
        trendingSelectionMenu(selected: section)
      }
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

extension SearchView {
  fileprivate var navigationTitle: String {
    let trimmedQuery = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    if viewModel.isShowingSearchResults, !trimmedQuery.isEmpty {
      return trimmedQuery
    }

    if let section = viewModel.selectedTrendingSection {
      return section.title
    }

    return "Search"
  }
}
