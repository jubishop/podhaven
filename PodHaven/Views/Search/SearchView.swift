// Copyright Justin Bishop, 2025

import FactoryKit
import IdentifiedCollections
import SwiftUI

struct SearchView: View {
  @InjectedObservable(\.navigation) private var navigation
  @InjectedObservable(\.sheet) private var sheet

  @State private var viewModel: SearchViewModel

  init(viewModel: SearchViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    IdentifiableNavigationStack(manager: navigation.search) {
      Group {
        if viewModel.isShowingSearchResults {
          searchResultsView
        } else {
          trendingView
            .safeAreaInset(edge: .top, spacing: 0) {
              categoryChipsView
            }
            .navigationTitle(viewModel.currentTrendingSection.title)
        }
      }
      .toolbar {
        manualEntryToolbarItem
      }
    }
    .searchable(
      text: $viewModel.searchText,
      placement: .automatic,
      prompt: Text("Search podcasts")
    )
    .task(viewModel.execute)
    .onChange(of: navigation.search.path) { _, path in
      if path.isEmpty { viewModel.observeCurrentDisplay() } else { viewModel.stopTasks() }
    }
    .onDisappear { viewModel.disappear() }
  }

  // MARK: - Content Builders

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
        viewModel.selectTrendingSection(section)
      },
      label: {
        HStack(spacing: 6) {
          section.icon.coloredImage
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

  @ViewBuilder
  private var searchResultsView: some View {
    let state = viewModel.searchState

    ScrollView {
      switch state {
      case .idle:
        placeholderView(
          icon: AppIcon.search,
          title: "Search for podcasts",
          message: "Enter a podcast name or keyword to get started."
        )

      case .loading, .loaded:
        if !viewModel.searchResults.isEmpty {
          resultsGrid(podcasts: viewModel.searchResults)
            .overlay(alignment: .top) {
              if state == .loading {
                loadingView(text: "Searching…")
                  .allowsHitTesting(false)
              }
            }
        } else if state == .loading {
          loadingView(text: "Searching…")
        } else {
          placeholderView(
            icon: AppIcon.search,
            title: "No results found",
            message: "Try different search terms or check your spelling."
          )
        }

      case .error(let message):
        errorView(title: "Search Error", message: message)
      }
    }
    .refreshable {
      await viewModel.refreshSearch()
    }
  }

  @ViewBuilder
  private var trendingView: some View {
    let section = viewModel.currentTrendingSection
    let state = section.state

    ScrollView {
      switch state {
      case .loaded, .loading, .idle:
        if !section.podcasts.isEmpty {
          resultsGrid(podcasts: section.podcasts)
            .overlay(alignment: .top) {
              if state == .loading {
                loadingView(text: "Fetching top \(section.title) podcasts…")
                  .allowsHitTesting(false)
              }
            }
        } else {
          loadingView(text: "Fetching top \(section.title) podcasts…")
        }

      case .error(let message):
        errorView(title: "Unable to Load", message: message)
      }
    }
    .refreshable {
      await viewModel.refreshCurrentTrendingSection()
    }
  }

  // MARK: - Section Grids

  @ViewBuilder
  private func resultsGrid(podcasts: IdentifiedArrayOf<DisplayedPodcast>) -> some View {
    ItemGrid(items: podcasts) { podcast in
      NavigationLink(
        value: Navigation.Destination.podcast(podcast),
        label: {
          VStack {
            SquareImage(image: podcast.image)
              .overlay(alignment: .topTrailing) {
                if podcast.subscribed {
                  subscribedBadge
                }
              }
            Text(podcast.title)
              .font(.caption)
              .lineLimit(1)
          }
        }
      )
      .buttonStyle(.plain)
    }
    .padding(.horizontal)
    .padding(.top)
  }

  private var subscribedBadge: some View {
    Image(systemName: "checkmark.circle.fill")
      .font(.system(size: 14, weight: .semibold))
      .foregroundStyle(.green, .white)
      .padding(4)
      .background(.ultraThinMaterial, in: Circle())
      .shadow(radius: 1)
  }

  // MARK: - Toolbar

  @ToolbarContentBuilder
  private var manualEntryToolbarItem: some ToolbarContent {
    ToolbarItem(placement: .secondaryAction) {
      Button(
        action: {
          sheet {
            ManualFeedEntryView(viewModel: ManualFeedEntryViewModel())
          }
        },
        label: {
          Label("Add Feed", systemImage: AppIcon.manualEntry.systemImageName)
        }
      )
      .accessibilityLabel("Add Feed URL manually")
    }
  }

  // MARK: - Reusable Views / Data

  private func loadingView(text: String) -> some View {
    ProgressView(text)
      .padding(.vertical, 24)
      .frame(maxWidth: .infinity, alignment: .center)
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
    placeholderView(icon: AppIcon.error, title: title, message: message)
  }
}

// MARK: - Preview

#if DEBUG
#Preview {
  SearchView(viewModel: SearchViewModel())
    .preview()
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
    }
}
#endif
