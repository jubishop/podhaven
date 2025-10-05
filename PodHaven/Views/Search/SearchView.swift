// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct SearchView: View {
  @InjectedObservable(\.navigation) private var navigation
  @InjectedObservable(\.sheet) private var sheet
  @InjectedObservable(\.searchViewModel) private var viewModel

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
    .task(viewModel.execute)
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
        ScrollView {
          searchGrid
            .padding(.horizontal)
            .padding(.top)
        }
      }
    }
  }

  @ViewBuilder
  private var trendingView: some View {
    switch viewModel.currentTrendingSection.state {
    case .idle, .loading:
      loadingView(text: "Fetching top podcasts…")

    case .error(let message):
      ScrollView {
        errorView(title: "Unable to Load", message: message)
          .padding(.top)
      }
      .refreshable {
        await viewModel.refreshCurrentTrendingSection()
      }

    case .loaded:
      ScrollView {
        trendingGrid
          .padding(.horizontal)
          .padding(.top)
      }
      .refreshable {
        await viewModel.refreshCurrentTrendingSection()
      }
    }
  }

  // MARK: - Section Rendering

  @ViewBuilder
  private var searchGrid: some View {
    ItemGrid(items: viewModel.searchResults, id: \.feedURL, minimumGridSize: gridItemSize) {
      podcast in
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

  @ViewBuilder
  private var trendingSelectionMenu: some View {
    Menu {
      ForEach(viewModel.trendingSections) { option in
        option.icon.labelButton {
          viewModel.selectTrendingSection(option.id)
        }
      }
    } label: {
      viewModel.currentTrendingSection.icon.coloredLabel
        .font(.title2.weight(.semibold))
    }
  }

  @ViewBuilder
  private var trendingGrid: some View {
    ItemGrid(items: viewModel.currentTrendingSection.podcasts, minimumGridSize: gridItemSize) {
      podcast in
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
      viewModel.currentTrendingSection.state == .loaded
    {
      ToolbarItem(placement: .primaryAction) {
        trendingSelectionMenu
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

    return viewModel.currentTrendingSection.title
  }
}
